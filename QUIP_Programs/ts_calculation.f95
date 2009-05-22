program ts_main 
  use libAtoms_module
  use QUIP_module 
  use ts_module
#ifdef HAVE_CP2K
  use cp2k_driver_module
#endif
  use tsParams_module

  implicit none

  type(Dynamicalsystem) :: ds_in, ds_fin 
  type(Potential)     :: classicalpot, qmpot
  type(MetaPotential) :: simple_metapot, hybrid_metapot
  type(Atoms)         :: at_in, at_fin, at_image
  type(inoutput)      :: xmlfile, in_image, in_in, in_fin, file_res
  type(Cinoutput)     :: outimage 
  type(TS)            :: tts 
  type(Dictionary)    :: metapot_params
  type(MPI_Context)   :: mpi
  type(tsParams)      :: params

  real(dp), allocatable :: forces(:,:)
  integer               :: niter, steps, im
  character(len=STRING_LENGTH) :: xmlfilename
  real(dp), allocatable, dimension(:,:) :: conf

  call initialise(mpi)

  if (mpi%active) then
     call system_initialise (common_seed = .true., enable_timing=.true., mpi_all_inoutput=.false.)
     call print('MPI run with '//mpi%n_procs//' processes')
  else
     call system_initialise( enable_timing=.true.)
     call print('Serial run')
  end if

  xmlfilename = 'ts.xml'
  call print_title('Initialisation')
  call initialise(params)

  call print('Reading parameters from file '//trim(xmlfilename))
  call initialise(xmlfile,xmlfilename,INPUT)
  call read_xml(params,xmlfile)
  call verbosity_push(params%io_verbosity)   ! Set base verbosity
  call print(params)

  call print ("Initialising classical potential with args " // trim(params%classical_args) &
       // " from file " // trim(xmlfilename))
  call rewind(xmlfile)
  call initialise(classicalpot, params%classical_args, xmlfile, mpi_obj = mpi)
  call Print(classicalpot)

  call print('Initialising metapotential')
  call initialise(simple_metapot, 'Simple', classicalpot, mpi_obj = mpi)
  call print(simple_metapot)

  if (params%simulation_hybrid) then
     call print ("Initialising QM potential with args " // trim(params%qm_args) &
          // " from file " // trim(xmlfilename))
     call rewind(xmlfile)
     call initialise(qmpot, params%qm_args, xmlfile, mpi_obj=mpi)
     call finalise(xmlfile)
     call Print(qmpot)

     call initialise(metapot_params)
     call set_value(metapot_params,'qm_args_str',params%qm_args_str)
     call set_value(metapot_params,'method','force_mixing')
     call initialise(hybrid_metapot, 'ForceMixing '//write_string(metapot_params), &
             classicalpot, qmpot, mpi_obj=mpi)

     call print_title('Hybrid Metapotential')
     call print(hybrid_metapot)

     call finalise(metapot_params)
  end if

  call print_title('Initialising First and Last Image')
  call Initialise(in_in, trim(params%chain_first_conf), action=INPUT)
  call read_xyz(at_in, in_in)
  call Initialise(in_fin, trim(params%chain_last_conf), action=INPUT)
  call read_xyz(at_fin, in_fin)
  call Print('Setting neighbour cutoff to '//(cutoff(classicalpot))//' A.')
  call atoms_set_cutoff(at_in, cutoff(classicalpot))
  call atoms_set_cutoff(at_fin, cutoff(classicalpot))

  call initialise(ds_in,at_in)
  call initialise(ds_fin,at_fin)
! Fix atoms (if necessary) 
  if(params%chain_nfix.ne.0) then
    ds_in%atoms%move_mask(ds_in%atoms%N-params%chain_nfix+1:ds_in%atoms%N) = 0
  endif
  ds_in%Ndof = 3*count(ds_in%atoms%move_mask == 1)
  allocate(forces(3,at_in%N))

  tts%cos%N = params%chain_nimages 
! if you want to initialise interpolating between the first and last image
  if(.not.params%simulation_restart) then
     if(params%minim_end) then
        call Print_title('First Image Optimisation')
        if (.not. params%simulation_hybrid) then
          call calc_connect(ds_in%Atoms)
          steps = minim(simple_metapot, ds_in%atoms, method=params%minim_end_method, convergence_tol=params%minim_end_tol, &
             max_steps=params%minim_end_max_steps, linminroutine=params%minim_end_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.false., use_fire=trim(params%minim_end_method)=='fire', &
             args_str=params%classical_args_str, eps_guess=params%minim_end_eps_guess)
        else
          steps = minim(hybrid_metapot, ds_in%atoms, method=params%minim_end_method, convergence_tol=params%minim_end_tol, &
             max_steps=params%minim_end_max_steps, linminroutine=params%minim_end_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.false., use_fire=trim(params%minim_end_method)=='fire', &
             eps_guess=params%minim_end_eps_guess)
        end if

        call Print_title('Last Image Optimisation')
        if (.not. params%simulation_hybrid) then
          call calc_connect(ds_in%Atoms)
          steps = minim(simple_metapot, ds_fin%atoms, method=params%minim_end_method, convergence_tol=params%minim_end_tol, &
             max_steps=params%minim_end_max_steps, linminroutine=params%minim_end_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.false., use_fire=trim(params%minim_end_method)=='fire', &
             args_str=params%classical_args_str, eps_guess=params%minim_end_eps_guess)
        else
          steps = minim(hybrid_metapot, ds_fin%atoms, method=params%minim_end_method, convergence_tol=params%minim_end_tol, &
             max_steps=params%minim_end_max_steps, linminroutine=params%minim_end_linminroutine, &
             do_pos=.true., do_lat=.false., do_print=.false., use_fire=trim(params%minim_end_method)=='fire', &
             eps_guess=params%minim_end_eps_guess)
        end if
     endif
   
     call print_title('Initialisation of the chain of state interpolating between the first and last image')
     call initialise(tts,ds_in%atoms,ds_fin%atoms,params)

! if you want to start from previous configuration for the path
  else
     allocate(conf(tts%cos%N, 3 * at_in%N) )
     do im=1,tts%cos%N
       call Initialise(in_image, 'conf.'//im//'.xyz')
       call read_xyz(at_image, in_image)
       conf(im,:) = reshape(at_image%pos, (/3*at_image%N/) ) 
       call finalise(at_image)   
       call finalise(in_image)
     enddo
     call print_title('Initialisation of the chain of state using the guessed path')
     call initialise(tts,ds_in%atoms,conf, params)
  endif

  call print(tts, params, mpi)
  if (.not. mpi%active .or. (mpi%active .and.mpi%my_proc == 0)) then
     do im =1, tts%cos%N
       call initialise(outimage, 'image.'//im//'.xyz', action=OUTPUT)
       call write(outimage, tts%cos%image(im)%at)
       call finalise(outimage)
     enddo
  end if

  call initialise(file_res, "out.dat",OUTPUT)

  call print_title('Transition state calculation')
  if (.not. params%simulation_hybrid) then
     call calc(tts,simple_metapot,niter, params, file_res, mpi)
  else
     call calc(tts,hybrid_metapot, niter, params, file_res, mpi)
  endif
  call print('Number or Iterations :  ' // niter )

  if (.not. mpi%active .or. (mpi%active .and.mpi%my_proc == 0)) then
     do im =1, tts%cos%N 
       call initialise(outimage, 'final.'//im//'.xyz', action=OUTPUT)
       call write(outimage, tts%cos%image(im)%at)
       call finalise(outimage)
     enddo
  end if

  call finalise(ds_in)
  call finalise(ds_fin)
  call finalise(at_in)
  call finalise(at_fin)
  deallocate(forces)

  call system_finalise()

  end program ts_main 
