! H0 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
! H0 X
! H0 X   libAtoms+QUIP: atomistic simulation library
! H0 X
! H0 X   Portions of this code were written by
! H0 X     Albert Bartok-Partay, Silvia Cereda, Gabor Csanyi, James Kermode,
! H0 X     Ivan Solt, Wojciech Szlachta, Csilla Varnai, Steven Winfield.
! H0 X
! H0 X   Copyright 2006-2010.
! H0 X
! H0 X   These portions of the source code are released under the GNU General
! H0 X   Public License, version 2, http://www.gnu.org/copyleft/gpl.html
! H0 X
! H0 X   If you would like to license the source code under different terms,
! H0 X   please contact Gabor Csanyi, gabor@csanyi.net
! H0 X
! H0 X   Portions of this code were written by Noam Bernstein as part of
! H0 X   his employment for the U.S. Government, and are not subject
! H0 X   to copyright in the USA.
! H0 X
! H0 X
! H0 X   When using this software, please cite the following reference:
! H0 X
! H0 X   http://www.libatoms.org
! H0 X
! H0 X  Additional contributions by
! H0 X    Alessio Comisso, Chiara Gattinoni, and Gianpietro Moras
! H0 X
! H0 XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

! do various structural analysis to a trajcetory, save an intermediate file
! to be postprocessed (mean, variance, correlation, etc)
! #/vol density on a radial mesh
! #/vol density on a grid
! RDF, possibly as a function of distance of center from a fixed point
! to be added: ADF

module structure_analysis_module
use libatoms_module
implicit none
private

type analysis
  logical :: density_radial, density_grid, rdfd, integrated_rdfd, & !water
             geometry, & !general
             density_axial_silica, num_hbond_silica, water_orientation_silica !silica-water interface
  character(len=FIELD_LENGTH) :: outfilename
  character(len=FIELD_LENGTH) :: mask_str

  integer :: n_configs = 0

  real(dp) :: min_time, max_time
  integer :: min_frame, max_frame

  ! radial density stuff
  real(dp) :: radial_min_p, radial_bin_width
  integer :: radial_n_bins
  real(dp) :: radial_center(3)
  real(dp) :: radial_gaussian_sigma
  real(dp), allocatable :: radial_histograms(:,:)
  real(dp), allocatable :: radial_pos(:)

  !uniaxial density - for silica-water interface
  integer :: axial_axis !x:1,y:2,z:3
  real(dp) :: axial_bin_width
  integer :: axial_n_bins
  integer :: axial_silica_atoms
  real(dp) :: axial_gaussian_sigma
  logical :: axial_gaussian_smoothing
  real(dp), allocatable :: axial_histograms(:,:)
  real(dp), allocatable :: axial_pos(:)
  
  ! density grid stuff
  real(dp) :: grid_min_p(3), grid_bin_width(3)
  integer :: grid_n_bins(3)
  logical :: grid_gaussian_smoothing
  real(dp) :: grid_gaussian_sigma
  real(dp), allocatable :: grid_histograms(:,:,:,:)
  real(dp), allocatable :: grid_pos(:,:,:,:)

  ! rdfd stuff
  real(dp) :: rdfd_zone_center(3)
  character(FIELD_LENGTH) :: rdfd_center_mask_str, rdfd_neighbour_mask_str
  real(dp) :: rdfd_zone_width, rdfd_bin_width
  integer :: rdfd_n_zones, rdfd_n_bins
  logical :: rdfd_gaussian_smoothing
  real(dp) :: rdfd_gaussian_sigma
  real(dp), allocatable :: rdfds(:,:,:)
  real(dp), allocatable :: rdfd_zone_pos(:), rdfd_bin_pos(:)

  !geometry
  character(FIELD_LENGTH) :: geometry_filename
  type(Table) :: geometry_params
  integer :: geometry_central_atom
  real(dp), allocatable :: geometry_histograms(:,:)
  real(dp), allocatable :: geometry_pos(:)
  character(FIELD_LENGTH), allocatable :: geometry_label(:)

  !silica_numhb - hydrogen bond distribution for silica-water interface
  integer :: num_hbond_axis !x:1,y:2,z:3
  integer :: num_hbond_silica_atoms
  integer :: num_hbond_n_type=4
  integer :: num_hbond_n_bins
  logical :: num_hbond_gaussian_smoothing
  real(dp) :: num_hbond_gaussian_sigma
  real(dp), allocatable :: num_hbond_histograms(:,:,:)
  real(dp), allocatable :: integrated_num_hbond_histograms(:,:)
  integer, allocatable :: num_hbond_type_code(:)
  real(dp), allocatable :: num_hbond_bin_pos(:)
  character(FIELD_LENGTH), allocatable :: num_hbond_type_label(:)

  !silica_water_orientation - water orientation distribution for silica-water interface
  integer :: water_orientation_axis !x:1,y:2,z:3
  integer :: water_orientation_silica_atoms
  integer :: water_orientation_n_angle_bins
  integer :: water_orientation_n_pos_bins
  logical :: water_orientation_gaussian_smoothing
  real(dp) :: water_orientation_pos_gaussian_sigma
  !real(dp) :: water_orientation_angle_gaussian_sigma
  logical :: water_orientation_use_dipole
  logical :: water_orientation_use_HOHangle_bisector
  real(dp), allocatable :: water_orientation_histograms(:,:,:)
  real(dp), allocatable :: integrated_water_orientation_histograms(:,:)
  real(dp), allocatable :: water_orientation_pos_bin(:)
  real(dp), allocatable :: water_orientation_angle_bin(:)
  real(dp), allocatable :: water_orientation_angle_bin_w(:)

end type analysis

public :: analysis, analysis_read, check_analyses, do_analyses, print_analyses

interface reallocate_data
  module procedure reallocate_data_1d, reallocate_data_2d, reallocate_data_3d
end interface reallocate_data

contains

subroutine analysis_read(this, prev, args_str)
  type(analysis), intent(inout) :: this
  type(analysis), intent(in), optional :: prev
  character(len=*), optional, intent(in) :: args_str

  type(Dictionary) :: params
  integer :: dummy_i_1
  character(len=FIELD_LENGTH) :: dummy_c_1, dummy_c_2
  logical :: dummy_l_1, dummy_l_2

  call initialise(params)
  call param_register(params, 'infile', '', dummy_c_1)
  call param_register(params, 'commandfile', '', dummy_c_2)
  call param_register(params, 'decimation', '0', dummy_i_1)
  call param_register(params, 'infile_is_list', 'F', dummy_l_1)
  call param_register(params, 'quiet', 'F', dummy_l_2)

  if (.not. present(prev)) then
    ! general
    this%outfilename=''
    this%mask_str = ''
    call param_register(params, 'outfile', 'stdout', this%outfilename)
    call param_register(params, 'AtomMask', '', this%mask_str)
    call param_register(params, 'min_time', '-1.0', this%min_time)
    call param_register(params, 'max_time', '-1.0', this%max_time)
    call param_register(params, 'min_frame', '-1', this%min_frame)
    call param_register(params, 'max_frame', '-1', this%max_frame)
    call param_register(params, 'density_radial', 'F', this%density_radial)
    call param_register(params, 'density_grid', 'F', this%density_grid)
    call param_register(params, 'rdfd', 'F', this%rdfd)
    call param_register(params, 'geometry', 'F', this%geometry)
    call param_register(params, 'density_axial_silica', 'F', this%density_axial_silica)
    call param_register(params, 'num_hbond_silica', 'F', this%num_hbond_silica)
    call param_register(params, 'water_orientation_silica', 'F', this%water_orientation_silica)

    ! radial density
    call param_register(params, 'radial_min_p', "0.0", this%radial_min_p)
    call param_register(params, 'radial_bin_width', '-1.0', this%radial_bin_width)
    call param_register(params, 'radial_n_bins', '-1', this%radial_n_bins)
    call param_register(params, 'radial_center', '0.0 0.0 0.0', this%radial_center)
    call param_register(params, 'radial_sigma', '1.0', this%radial_gaussian_sigma)

    ! grid density
    call param_register(params, 'grid_min_p', '0.0 0.0 0.0', this%grid_min_p)
    call param_register(params, 'grid_bin_width', '-1.0 -1.0 -1.0', this%grid_bin_width)
    call param_register(params, 'grid_n_bins', '-1 -1 -1', this%grid_n_bins)
    call param_register(params, 'grid_gaussian', 'F', this%grid_gaussian_smoothing)
    call param_register(params, 'grid_sigma', '1.0', this%grid_gaussian_sigma)

    ! rdfd
    call param_register(params, 'rdfd_zone_center', '0.0 0.0 0.0', this%rdfd_zone_center)
    call param_register(params, 'rdfd_bin_width', '-1', this%rdfd_bin_width)
    call param_register(params, 'rdfd_n_bins', '-1', this%rdfd_n_bins)
    call param_register(params, 'rdfd_zone_width', '-1.0', this%rdfd_zone_width)
    call param_register(params, 'rdfd_n_zones', '1', this%rdfd_n_zones)
    this%rdfd_center_mask_str=''
    call param_register(params, 'rdfd_center_mask', '', this%rdfd_center_mask_str)
    this%rdfd_neighbour_mask_str=''
    call param_register(params, 'rdfd_neighbour_mask', '', this%rdfd_neighbour_mask_str)
    call param_register(params, 'rdfd_gaussian', 'F', this%rdfd_gaussian_smoothing)
    call param_register(params, 'rdfd_sigma', '0.1', this%rdfd_gaussian_sigma)

    ! geometry
    this%geometry_filename=''
    call param_register(params, 'geometry_filename', '', this%geometry_filename)
    call param_register(params, 'geometry_central_atom', '-1', this%geometry_central_atom)

    ! uniaxial density silica
    call param_register(params, 'axial_n_bins', '-1', this%axial_n_bins)
    !call param_register(params, 'axial_bin_width', '-1.0', this%axial_bin_width)
    call param_register(params, 'axial_axis', '-1', this%axial_axis)
    call param_register(params, 'axial_silica_atoms', '-1', this%axial_silica_atoms)
    call param_register(params, 'axial_gaussian', 'F', this%axial_gaussian_smoothing)
    call param_register(params, 'axial_sigma', '1.0', this%axial_gaussian_sigma)
    !call param_register(params, 'axial_atommask', '', this%axial_atommask)

    ! num_hbond_silica
    call param_register(params, 'num_hbond_n_bins', '-1', this%num_hbond_n_bins)
    call param_register(params, 'num_hbond_axis', '0', this%num_hbond_axis)
    call param_register(params, 'num_hbond_silica_atoms', '0', this%num_hbond_silica_atoms)
    call param_register(params, 'num_hbond_gaussian', 'F', this%num_hbond_gaussian_smoothing)
    call param_register(params, 'num_hbond_sigma', '1.0', this%num_hbond_gaussian_sigma)

    ! water_orientation_silica
    call param_register(params, 'water_orientation_n_pos_bins', '-1', this%water_orientation_n_pos_bins)
    call param_register(params, 'water_orientation_n_angle_bins', '-1', this%water_orientation_n_angle_bins)
    call param_register(params, 'water_orientation_axis', '0', this%water_orientation_axis)
    call param_register(params, 'water_orientation_silica_atoms', '0', this%water_orientation_silica_atoms)
    call param_register(params, 'water_orientation_gaussian', 'F', this%water_orientation_gaussian_smoothing)
    call param_register(params, 'water_orientation_pos_sigma', '1.0', this%water_orientation_pos_gaussian_sigma)
    !call param_register(params, 'water_orientation_angle_sigma', '1.0', this%water_orientation_angle_gaussian_sigma)
    call param_register(params, 'water_orientation_use_dipole', 'F', this%water_orientation_use_dipole)
    call param_register(params, 'water_orientation_use_HOHangle_bisector', 'F', this%water_orientation_use_HOHangle_bisector)

  else
    ! general
    call param_register(params, 'outfile', trim(prev%outfilename), this%outfilename)
    call param_register(params, 'AtomMask', trim(prev%mask_str), this%mask_str)
    call param_register(params, 'min_time', ''//prev%min_time, this%min_time)
    call param_register(params, 'max_time', ''//prev%max_time, this%max_time)
    call param_register(params, 'min_frame', ''//prev%min_frame, this%min_frame)
    call param_register(params, 'max_frame', ''//prev%max_frame, this%max_frame)
    call param_register(params, 'density_radial', ''//prev%density_radial, this%density_radial)
    call param_register(params, 'density_grid', ''//prev%density_grid, this%density_grid)
    call param_register(params, 'rdfd', ''//prev%rdfd, this%rdfd)
    call param_register(params, 'geometry', ''//prev%geometry, this%geometry)

    ! radial density
    call param_register(params, 'radial_min_p', ''//this%radial_min_p, this%radial_min_p)
    call param_register(params, 'radial_bin_width', ''//this%radial_bin_width, this%radial_bin_width)
    call param_register(params, 'radial_n_bins', ''//this%radial_n_bins, this%radial_n_bins)
    call param_register(params, 'radial_center', ''//prev%radial_center, this%radial_center)
    call param_register(params, 'radial_sigma', ''//prev%radial_gaussian_sigma, this%radial_gaussian_sigma)

    ! grid density
    call param_register(params, 'grid_min_p', ''//prev%grid_min_p, this%grid_min_p)
    call param_register(params, 'grid_bin_width', ''//prev%grid_bin_width, this%grid_bin_width)
    call param_register(params, 'grid_n_bins', ''//prev%grid_n_bins, this%grid_n_bins)
    call param_register(params, 'grid_gaussian', ''//prev%grid_gaussian_smoothing, this%grid_gaussian_smoothing)
    call param_register(params, 'grid_sigma', ''//prev%grid_gaussian_sigma, this%grid_gaussian_sigma)

    ! rdfd
    call param_register(params, 'rdfd_zone_center', ''//prev%rdfd_zone_center, this%rdfd_zone_center)
    call param_register(params, 'rdfd_bin_width', ''//prev%rdfd_bin_width, this%rdfd_bin_width)
    call param_register(params, 'rdfd_n_bins', ''//prev%rdfd_n_bins, this%rdfd_n_bins)
    call param_register(params, 'rdfd_zone_width', ''//prev%rdfd_zone_width, this%rdfd_zone_width)
    call param_register(params, 'rdfd_n_zones', ''//prev%rdfd_n_zones, this%rdfd_n_zones)
    call param_register(params, 'rdfd_center_mask', trim(prev%rdfd_center_mask_str), this%rdfd_center_mask_str)
    call param_register(params, 'rdfd_neighbour_mask', trim(prev%rdfd_neighbour_mask_str), this%rdfd_neighbour_mask_str)
    call param_register(params, 'rdfd_gaussian', ''//prev%rdfd_gaussian_smoothing, this%rdfd_gaussian_smoothing)
    call param_register(params, 'rdfd_sigma', ''//prev%rdfd_gaussian_sigma, this%rdfd_gaussian_sigma)

    ! geometry
    call param_register(params, 'geometry_filename', ''//trim(prev%geometry_filename), this%geometry_filename)
    call param_register(params, 'geometry_central_atom', ''//prev%geometry_central_atom, this%geometry_central_atom)

    ! uniaxial density silica
    call param_register(params, 'axial_n_bins', ''//prev%axial_n_bins, this%axial_n_bins)
    !call param_register(params, 'axial_bin_width', ''//prev%axial_bin_width, this%axial_bin_width)
    call param_register(params, 'axial_axis', ''//prev%axial_axis, this%axial_axis)
    call param_register(params, 'axial_silica_atoms', ''//prev%axial_silica_atoms, this%axial_silica_atoms)
    call param_register(params, 'axial_gaussian', ''//prev%axial_gaussian_smoothing, this%axial_gaussian_smoothing)
    call param_register(params, 'axial_sigma', ''//prev%axial_gaussian_sigma, this%axial_gaussian_sigma)
    !call param_register(params, 'axial_atommask', ''//prev%axial_atommask, this%axial_atommask)

    ! num_hbond_silica
    call param_register(params, 'num_hbond_n_bins', ''//prev%num_hbond_n_bins, this%num_hbond_n_bins)
    call param_register(params, 'num_hbond_axis', ''//prev%num_hbond_axis, this%num_hbond_axis)
    call param_register(params, 'num_hbond_silica_atoms', ''//prev%num_hbond_silica_atoms, this%num_hbond_silica_atoms)
    call param_register(params, 'num_hbond_gaussian', ''//prev%num_hbond_gaussian_smoothing, this%num_hbond_gaussian_smoothing)
    call param_register(params, 'num_hbond_sigma', ''//prev%num_hbond_gaussian_sigma, this%num_hbond_gaussian_sigma)

    ! water_orientation_silica
    call param_register(params, 'water_orientation_n_pos_bins', ''//prev%water_orientation_n_pos_bins, this%water_orientation_n_pos_bins)
    call param_register(params, 'water_orientation_n_angle_bins', ''//prev%water_orientation_n_angle_bins, this%water_orientation_n_angle_bins)
    call param_register(params, 'water_orientation_axis', ''//prev%water_orientation_axis, this%water_orientation_axis)
    call param_register(params, 'water_orientation_silica_atoms', ''//prev%water_orientation_silica_atoms, this%water_orientation_silica_atoms)
    call param_register(params, 'water_orientation_gaussian', ''//prev%water_orientation_gaussian_smoothing, this%water_orientation_gaussian_smoothing)
    call param_register(params, 'water_orientation_pos_sigma', ''//prev%water_orientation_pos_gaussian_sigma, this%water_orientation_pos_gaussian_sigma)
    !call param_register(params, 'water_orientation_angle_sigma', ''//prev%water_orientation_angle_gaussian_sigma, this%water_orientation_angle_gaussian_sigma)
    call param_register(params, 'water_orientation_use_dipole', ''//prev%water_orientation_use_dipole, this%water_orientation_use_dipole)
    call param_register(params, 'water_orientation_use_HOHangle_bisector', ''//prev%water_orientation_use_HOHangle_bisector, this%water_orientation_use_HOHangle_bisector)

  endif

  if (present(args_str)) then
    if (.not. param_read_line(params, trim(args_str), ignore_unknown=.false.)) &
      call system_abort("analysis_read failed to parse string '"//trim(args_str)//"'")
  else
    if (.not. param_read_args(params, do_check=.true.)) &
      call system_abort("analysis_read failed to parse command line arguments")
  endif

  if (count ( (/ this%density_radial, this%density_grid, this%rdfd, this%geometry, this%density_axial_silica, this%num_hbond_silica, this%water_orientation_silica /) ) /= 1) &
    call system_abort("Specified "//count( (/ this%density_radial, this%density_grid, this%rdfd, this%geometry, this%density_axial_silica, this%num_hbond_silica, this%water_orientation_silica /) )//" types of analysis.  Possiblities: density_radial, density_grid, rdfd, geometry, density_axial_silica, num_hbond_silica, water_orientation_silica.")

end subroutine analysis_read

subroutine check_analyses(a)
  type(analysis), intent(inout) :: a(:)

  integer :: i_a

  do i_a=1, size(a)
    if (a(i_a)%density_radial) then !density_radial
      if (a(i_a)%radial_bin_width <= 0.0_dp) call system_abort("analysis " // i_a // " has radial_bin_width="//a(i_a)%radial_bin_width//" <= 0.0")
      if (a(i_a)%radial_n_bins <= 0) call system_abort("analysis " // i_a // " has radial_n_bins="//a(i_a)%radial_n_bins//" <= 0")
    else if (a(i_a)%density_grid) then !density_grid
      if (any(a(i_a)%grid_bin_width <= 0.0_dp)) call system_abort("analysis " // i_a // " has grid_bin_width="//a(i_a)%grid_bin_width//" <= 0.0")
      if (any(a(i_a)%grid_n_bins <= 0)) call system_abort("analysis " // i_a // " has grid_n_bins="//a(i_a)%grid_n_bins//" <= 0")
    else if (a(i_a)%rdfd) then !rdfd
      if (a(i_a)%rdfd_bin_width <= 0.0_dp) call system_abort("analysis " // i_a // " has rdfd_bin_width="//a(i_a)%rdfd_bin_width//" <= 0.0")
      if (a(i_a)%rdfd_n_bins <= 0) call system_abort("analysis " // i_a // " has rdfd_n_bins="//a(i_a)%rdfd_n_bins//" <= 0")
      if (a(i_a)%rdfd_n_zones <= 0) call system_abort("analysis " // i_a // " has rdfd_n_zones="//a(i_a)%rdfd_n_zones//" <= 0")
    else if (a(i_a)%geometry) then !geometry
      if (trim(a(i_a)%geometry_filename)=="") call system_abort("analysis "//i_a//" has empty geometry_filename")
      !read geometry parameters to calculate from the file into a table
      call read_geometry_params(a(i_a),trim(a(i_a)%geometry_filename))
      if (a(i_a)%geometry_params%N==0) call system_abort("analysis "//i_a//" has no geometry parameters to calculate")
    else if (a(i_a)%density_axial_silica) then !density_axial_silica
      if (a(i_a)%axial_n_bins <= 0) call system_abort("analysis " // i_a // " has axial_n_bins="//a(i_a)%axial_n_bins//" <= 0")
      if (.not. any(a(i_a)%axial_axis == (/1,2,3/))) call system_abort("analysis " // i_a // " has axial_axis="//a(i_a)%axial_axis//" /= 1, 2 or 3")
    else if (a(i_a)%num_hbond_silica) then !num_hbond_silica
      if (a(i_a)%num_hbond_n_bins <= 0) call system_abort("analysis " // i_a // " has num_hbond_n_bins="//a(i_a)%num_hbond_n_bins//" <= 0")
      if (.not. any(a(i_a)%num_hbond_axis == (/1,2,3/))) call system_abort("analysis " // i_a // " has num_hbond_axis="//a(i_a)%num_hbond_axis//" /= 1, 2 or 3")
    else if (a(i_a)%water_orientation_silica) then !water_orientation_silica
      if (a(i_a)%water_orientation_n_pos_bins <= 0) call system_abort("analysis " // i_a // " has water_orientation_n_pos_bins="//a(i_a)%water_orientation_n_pos_bins//" <= 0")
      if (a(i_a)%water_orientation_n_angle_bins <= 0) call system_abort("analysis " // i_a // " has water_orientation_n_angle_bins="//a(i_a)%water_orientation_n_angle_bins//" <= 0")
      if (.not. any(a(i_a)%water_orientation_axis == (/1,2,3/))) call system_abort("analysis " // i_a // " has water_orientation_axis="//a(i_a)%water_orientation_axis//" /= 1, 2 or 3")
      if (.not. count((/a(i_a)%water_orientation_use_HOHangle_bisector,a(i_a)%water_orientation_use_dipole/)) == 1) call system_abort("Exactly one of water_orientation_use_HOHangle_bisector and water_orientation_use_dipole must be one.")
    else
      call system_abort("check_analyses: no type of analysis set for " // i_a)
    endif
  end do
end subroutine check_analyses

subroutine do_analyses(a, time, frame, at)
  type(analysis), intent(inout) :: a(:)
  real(dp), intent(in) :: time
  integer, intent(in) :: frame
  type(Atoms), intent(inout) :: at

  integer :: i_a

  call map_into_cell(at)
!  at%t ravel = 0

  do i_a=1, size(a)

    if (do_this_analysis(a(i_a), time, frame)) then

      a(i_a)%n_configs = a(i_a)%n_configs + 1

      if (a(i_a)%density_radial) then !density_radial
        call reallocate_data(a(i_a)%radial_histograms, a(i_a)%n_configs, a(i_a)%radial_n_bins)
        if (a(i_a)%n_configs == 1) then
          allocate(a(i_a)%radial_pos(a(i_a)%radial_n_bins))
          call density_sample_radial_mesh_Gaussians(a(i_a)%radial_histograms(:,a(i_a)%n_configs), at, center_pos=a(i_a)%radial_center, &
            rad_bin_width=a(i_a)%radial_bin_width, n_rad_bins=a(i_a)%radial_n_bins, gaussian_sigma=a(i_a)%radial_gaussian_sigma, &
            mask_str=a(i_a)%mask_str, radial_pos=a(i_a)%radial_pos)
        else
          call density_sample_radial_mesh_Gaussians(a(i_a)%radial_histograms(:,a(i_a)%n_configs), at, center_pos=a(i_a)%radial_center, &
            rad_bin_width=a(i_a)%radial_bin_width, n_rad_bins=a(i_a)%radial_n_bins, gaussian_sigma= a(i_a)%radial_gaussian_sigma, &
            mask_str=a(i_a)%mask_str)
        endif
      else if (a(i_a)%density_grid) then !density_grid
        call reallocate_data(a(i_a)%grid_histograms, a(i_a)%n_configs, a(i_a)%grid_n_bins)
        if (a(i_a)%grid_gaussian_smoothing) then
          if (a(i_a)%n_configs == 1) then
            allocate(a(i_a)%grid_pos(3,a(i_a)%grid_n_bins(1),a(i_a)%grid_n_bins(2),a(i_a)%grid_n_bins(3)))
            call density_sample_rectilinear_mesh_Gaussians(a(i_a)%grid_histograms(:,:,:,a(i_a)%n_configs), at, a(i_a)%grid_min_p, &
              a(i_a)%grid_bin_width, a(i_a)%grid_n_bins, a(i_a)%grid_gaussian_sigma, a(i_a)%mask_str, a(i_a)%grid_pos)
          else
            call density_sample_rectilinear_mesh_Gaussians(a(i_a)%grid_histograms(:,:,:,a(i_a)%n_configs), at, a(i_a)%grid_min_p, &
              a(i_a)%grid_bin_width, a(i_a)%grid_n_bins, a(i_a)%grid_gaussian_sigma, a(i_a)%mask_str)
          endif
        else
          if (a(i_a)%n_configs == 1) then
            allocate(a(i_a)%grid_pos(3,a(i_a)%grid_n_bins(1),a(i_a)%grid_n_bins(2),a(i_a)%grid_n_bins(3)))
            call density_bin_rectilinear_mesh(a(i_a)%grid_histograms(:,:,:,a(i_a)%n_configs), at, a(i_a)%grid_min_p, a(i_a)%grid_bin_width, &
              a(i_a)%grid_n_bins, a(i_a)%mask_str, a(i_a)%grid_pos)
          else
            call density_bin_rectilinear_mesh(a(i_a)%grid_histograms(:,:,:,a(i_a)%n_configs), at, a(i_a)%grid_min_p, a(i_a)%grid_bin_width, &
              a(i_a)%grid_n_bins, a(i_a)%mask_str)
          endif
        endif
      else if (a(i_a)%rdfd) then !rdfd
        call reallocate_data(a(i_a)%rdfds, a(i_a)%n_configs, (/ a(i_a)%rdfd_n_bins, a(i_a)%rdfd_n_zones /) )
        if (a(i_a)%n_configs == 1) then
          allocate(a(i_a)%rdfd_bin_pos(a(i_a)%rdfd_n_bins))
          allocate(a(i_a)%rdfd_zone_pos(a(i_a)%rdfd_n_zones))
          call rdfd_calc(a(i_a)%rdfds(:,:,a(i_a)%n_configs), at, a(i_a)%rdfd_zone_center, a(i_a)%rdfd_bin_width, a(i_a)%rdfd_n_bins, &
            a(i_a)%rdfd_zone_width, a(i_a)%rdfd_n_zones, a(i_a)%rdfd_gaussian_smoothing, a(i_a)%rdfd_gaussian_sigma, &
            a(i_a)%rdfd_center_mask_str, a(i_a)%rdfd_neighbour_mask_str, &
            a(i_a)%rdfd_bin_pos, a(i_a)%rdfd_zone_pos)
        else
          call rdfd_calc(a(i_a)%rdfds(:,:,a(i_a)%n_configs), at, a(i_a)%rdfd_zone_center, a(i_a)%rdfd_bin_width, a(i_a)%rdfd_n_bins, &
            a(i_a)%rdfd_zone_width, a(i_a)%rdfd_n_zones, a(i_a)%rdfd_gaussian_smoothing, a(i_a)%rdfd_gaussian_sigma, &
            a(i_a)%rdfd_center_mask_str, a(i_a)%rdfd_neighbour_mask_str)
        endif
      else if (a(i_a)%geometry) then !geometry
        call reallocate_data(a(i_a)%geometry_histograms, a(i_a)%n_configs, a(i_a)%geometry_params%N)
        if (a(i_a)%n_configs == 1) then
          allocate(a(i_a)%geometry_pos(a(i_a)%geometry_params%N))
          allocate(a(i_a)%geometry_label(a(i_a)%geometry_params%N))
          call geometry_calc(a(i_a)%geometry_histograms(:,a(i_a)%n_configs), at, a(i_a)%geometry_params, a(i_a)%geometry_central_atom, &
               a(i_a)%geometry_pos(1:a(i_a)%geometry_params%N), a(i_a)%geometry_label(1:a(i_a)%geometry_params%N))
        else
          call geometry_calc(a(i_a)%geometry_histograms(:,a(i_a)%n_configs), at, a(i_a)%geometry_params, a(i_a)%geometry_central_atom)
        endif
      else if (a(i_a)%density_axial_silica) then !density_axial_silica
        call reallocate_data(a(i_a)%axial_histograms, a(i_a)%n_configs, a(i_a)%axial_n_bins)
        if (a(i_a)%n_configs == 1) then
           allocate(a(i_a)%axial_pos(a(i_a)%axial_n_bins))
           call density_axial_calc(a(i_a)%axial_histograms(:,a(i_a)%n_configs), at, &
             axis=a(i_a)%axial_axis, silica_center_i=a(i_a)%axial_silica_atoms, &
             n_bins=a(i_a)%axial_n_bins, &
             gaussian_smoothing=a(i_a)%axial_gaussian_smoothing, &
             gaussian_sigma=a(i_a)%axial_gaussian_sigma, &
             mask_str=a(i_a)%mask_str, axial_pos=a(i_a)%axial_pos)
        else
           call density_axial_calc(a(i_a)%axial_histograms(:,a(i_a)%n_configs), at, &
             axis=a(i_a)%axial_axis, silica_center_i=a(i_a)%axial_silica_atoms, &
             n_bins=a(i_a)%axial_n_bins, &
             gaussian_smoothing=a(i_a)%axial_gaussian_smoothing, &
             gaussian_sigma=a(i_a)%axial_gaussian_sigma, &
             mask_str=a(i_a)%mask_str)
        endif
      else if (a(i_a)%num_hbond_silica) then !num_hbond_silica
        a(i_a)%num_hbond_n_type = 4
        call reallocate_data(a(i_a)%num_hbond_histograms, a(i_a)%n_configs, (/a(i_a)%num_hbond_n_bins,a(i_a)%num_hbond_n_type/)) !4: ss, sw, ws, ww
        if (a(i_a)%n_configs == 1) then
           allocate(a(i_a)%num_hbond_bin_pos(a(i_a)%num_hbond_n_bins))
           allocate(a(i_a)%num_hbond_type_code(4))
           allocate(a(i_a)%num_hbond_type_label(4))
           call num_hbond_calc(a(i_a)%num_hbond_histograms(:,:,a(i_a)%n_configs), at, &
             axis=a(i_a)%num_hbond_axis, silica_center_i=a(i_a)%num_hbond_silica_atoms, &
             n_bins=a(i_a)%num_hbond_n_bins, &
             gaussian_smoothing=a(i_a)%num_hbond_gaussian_smoothing, &
             gaussian_sigma=a(i_a)%num_hbond_gaussian_sigma, &
             mask_str=a(i_a)%mask_str, num_hbond_pos=a(i_a)%num_hbond_bin_pos, &
             num_hbond_type_code=a(i_a)%num_hbond_type_code, &
             num_hbond_type_label=a(i_a)%num_hbond_type_label)
        else
           call num_hbond_calc(a(i_a)%num_hbond_histograms(:,:,a(i_a)%n_configs), at, &
             axis=a(i_a)%num_hbond_axis, silica_center_i=a(i_a)%num_hbond_silica_atoms, &
             n_bins=a(i_a)%num_hbond_n_bins, &
             gaussian_smoothing=a(i_a)%num_hbond_gaussian_smoothing, &
             gaussian_sigma=a(i_a)%num_hbond_gaussian_sigma, &
             mask_str=a(i_a)%mask_str)
        endif
      else if (a(i_a)%water_orientation_silica) then !water_orientation_silica
        call reallocate_data(a(i_a)%water_orientation_histograms, a(i_a)%n_configs, (/ a(i_a)%water_orientation_n_angle_bins, a(i_a)%water_orientation_n_pos_bins /) )
        if (a(i_a)%n_configs == 1) then
          allocate(a(i_a)%water_orientation_angle_bin(a(i_a)%water_orientation_n_angle_bins))
          allocate(a(i_a)%water_orientation_angle_bin_w(a(i_a)%water_orientation_n_angle_bins))
          allocate(a(i_a)%water_orientation_pos_bin(a(i_a)%water_orientation_n_pos_bins))
          call water_orientation_calc(a(i_a)%water_orientation_histograms(:,:,a(i_a)%n_configs), at, &
             axis=a(i_a)%water_orientation_axis, silica_center_i=a(i_a)%water_orientation_silica_atoms, &
            n_pos_bins=a(i_a)%water_orientation_n_pos_bins, n_angle_bins=a(i_a)%water_orientation_n_angle_bins, &
            gaussian_smoothing=a(i_a)%water_orientation_gaussian_smoothing, &
            pos_gaussian_sigma=a(i_a)%water_orientation_pos_gaussian_sigma, &
            !angle_gaussian_sigma=a(i_a)%water_orientation_angle_gaussian_sigma, &
            pos_bin=a(i_a)%water_orientation_pos_bin, angle_bin=a(i_a)%water_orientation_angle_bin, &
            angle_bin_w=a(i_a)%water_orientation_angle_bin_w, &
            use_dipole_rather_than_angle_bisector=a(i_a)%water_orientation_use_dipole)
        else
          call water_orientation_calc(a(i_a)%water_orientation_histograms(:,:,a(i_a)%n_configs), at, &
             axis=a(i_a)%water_orientation_axis, silica_center_i=a(i_a)%water_orientation_silica_atoms, &
            n_pos_bins=a(i_a)%water_orientation_n_pos_bins, n_angle_bins=a(i_a)%water_orientation_n_angle_bins, &
            gaussian_smoothing=a(i_a)%water_orientation_gaussian_smoothing, &
            pos_gaussian_sigma=a(i_a)%water_orientation_pos_gaussian_sigma, &
            !angle_gaussian_sigma=a(i_a)%water_orientation_angle_gaussian_sigma, &
            angle_bin_w=a(i_a)%water_orientation_angle_bin_w, &
            use_dipole_rather_than_angle_bisector=a(i_a)%water_orientation_use_dipole)
        endif
      else 
        call system_abort("do_analyses: no type of analysis set for " // i_a)
      endif
    end if ! do this analysis
  end do
end subroutine do_analyses

function do_this_analysis(this, time, frame)
  type(analysis), intent(in) :: this
  real(dp), intent(in), optional :: time
  integer, intent(in), optional :: frame
  logical :: do_this_analysis

  do_this_analysis = .true.

  if (this%min_time > 0.0_dp) then
    if (.not. present(time)) call system_abort("analysis has non-zero min_time, but no time specified")
    if (time < 0.0_dp) call system_abort("analysis has non-zero min_time, but invalid time < 0")
    if (time < this%min_time) then
      do_this_analysis = .false.
    endif
  endif
  if (this%max_time > 0.0_dp) then
    if (.not. present(time)) call system_abort("analysis has non-zero max_time, but no time specified")
    if (time < 0.0_dp) call system_abort("analysis has non-zero max_time, but invalid time < 0")
    if (time > this%max_time) then
      do_this_analysis = .false.
    endif
  endif

  if (this%min_frame > 0) then
    if (.not. present(frame)) call system_abort("analysis has non-zero min_frame, but no frame specified")
    if (frame < 0) call system_abort("analysis has non-zero min_frame, but invalid frame < 0")
    if (frame < this%min_frame) then
      do_this_analysis = .false.
    endif
  endif
  if (this%max_frame > 0) then
    if (.not. present(frame)) call system_abort("analysis has non-zero max_frame, but no frame specified")
    if (frame < 0) call system_abort("analysis has non-zero max_frame, but invalid frame < 0")
    if (frame > this%max_frame) then
      do_this_analysis = .false.
    endif
  endif

end function do_this_analysis

subroutine print_analyses(a)
  type(analysis), intent(inout) :: a(:)

  type(inoutput) :: outfile
  integer :: i, i1, i2, i3, i_a
  real(dp), allocatable :: integrated_rdfds(:,:)

  do i_a=1, size(a)
    call initialise(outfile, a(i_a)%outfilename, OUTPUT)
    if (a(i_a)%outfilename == "stdout") then
      outfile%prefix="ANALYSIS_"//i_a
    endif

    if (a(i_a)%n_configs <= 0) then
      call print("# NO DATA", file=outfile)
    else
      if (a(i_a)%density_radial) then !density_radial
        call print("# radial density histogram", file=outfile)
        call print("n_bins="//a(i_a)%radial_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i=1, a(i_a)%radial_n_bins
          call print(a(i_a)%radial_pos(i), file=outfile)
        end do
        do i=1, a(i_a)%n_configs
          call print(a(i_a)%radial_histograms(:,i), file=outfile)
        end do
      else if (a(i_a)%density_grid) then !density_grid
        call print("# grid density histogram", file=outfile)
        call print("n_bins="//a(i_a)%grid_n_bins(1)*a(i_a)%grid_n_bins(2)*a(i_a)%grid_n_bins(3)//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%grid_n_bins(1)
        do i2=1, a(i_a)%grid_n_bins(2)
        do i3=1, a(i_a)%grid_n_bins(3)
          call print(""//a(i_a)%grid_pos(:,i1,i2,i3), file=outfile)
        end do
        end do
        end do
        do i=1, a(i_a)%n_configs
          call print(""//reshape(a(i_a)%grid_histograms(:,:,:,i), (/ a(i_a)%grid_n_bins(1)*a(i_a)%grid_n_bins(2)*a(i_a)%grid_n_bins(3) /) ), file=outfile)
        end do
      else if (a(i_a)%rdfd) then !rdfd
        call print("# rdfd", file=outfile)
        call print("n_bins="//a(i_a)%rdfd_n_zones*a(i_a)%rdfd_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%rdfd_n_zones
        do i2=1, a(i_a)%rdfd_n_bins
          if (a(i_a)%rdfd_zone_width > 0.0_dp) then
            call print(""//a(i_a)%rdfd_zone_pos(i1)//" "//a(i_a)%rdfd_bin_pos(i2), file=outfile)
          else
            call print(""//a(i_a)%rdfd_bin_pos(i2), file=outfile)
          endif
        end do
        end do
        do i=1, a(i_a)%n_configs
          call print(""//reshape(a(i_a)%rdfds(:,:,i), (/ a(i_a)%rdfd_n_zones*a(i_a)%rdfd_n_bins /) ), file=outfile)
        end do

        call print("", file=outfile)
        call print("", file=outfile)
        call print("# integrated_rdfd", file=outfile)
        call print("n_bins="//a(i_a)%rdfd_n_zones*a(i_a)%rdfd_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%rdfd_n_zones
        do i2=1, a(i_a)%rdfd_n_bins
          if (a(i_a)%rdfd_zone_width > 0.0_dp) then
            call print(""//a(i_a)%rdfd_zone_pos(i1)//" "//a(i_a)%rdfd_bin_pos(i2), file=outfile)
          else
            call print(""//a(i_a)%rdfd_bin_pos(i2), file=outfile)
          endif
        end do
        end do
	allocate(integrated_rdfds(a(i_a)%rdfd_n_bins,a(i_a)%rdfd_n_zones))
	integrated_rdfds = 0.0_dp
        do i=1, a(i_a)%n_configs
	  integrated_rdfds = 0.0_dp
	  do i1=1, a(i_a)%rdfd_n_zones
	    do i2=2, a(i_a)%rdfd_n_bins
	      integrated_rdfds(i2,i1) = integrated_rdfds(i2-1,i1) + &
		(a(i_a)%rdfd_bin_pos(i2)-a(i_a)%rdfd_bin_pos(i2-1))* &
		4.0_dp*PI*((a(i_a)%rdfd_bin_pos(i2)**2)*a(i_a)%rdfds(i2,i1,i)+(a(i_a)%rdfd_bin_pos(i2-1)**2)*a(i_a)%rdfds(i2-1,i1,i))/2.0_dp
	    end do
	  end do
          call print(""//reshape(integrated_rdfds(:,:), (/ a(i_a)%rdfd_n_zones*a(i_a)%rdfd_n_bins /) ), file=outfile)
        end do
	deallocate(integrated_rdfds)

      else if (a(i_a)%geometry) then !geometry
        call print("# geometry histogram", file=outfile)
        call print("n_bins="//a(i_a)%geometry_params%N//" n_data="//a(i_a)%n_configs, file=outfile)
        do i=1, a(i_a)%geometry_params%N
!          call print(a(i_a)%geometry_pos(i), file=outfile)
          call print(trim(a(i_a)%geometry_label(i)), file=outfile)
        end do
        do i=1, a(i_a)%n_configs
          call print(a(i_a)%geometry_histograms(:,i), file=outfile)
        end do

      else if (a(i_a)%density_axial_silica) then !density_axial_silica
        call print("# uniaxial density histogram in direction "//a(i_a)%axial_axis, file=outfile)
        call print("n_bins="//a(i_a)%axial_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i=1, a(i_a)%axial_n_bins
          call print(a(i_a)%axial_pos(i), file=outfile)
        end do
        do i=1, a(i_a)%n_configs
          call print(a(i_a)%axial_histograms(:,i), file=outfile)
        end do

      else if (a(i_a)%num_hbond_silica) then !num_hbond_silica
        !header
        call print("# num_hbond_silica in direction "//a(i_a)%num_hbond_axis, file=outfile)
        call print("n_bins="//a(i_a)%num_hbond_n_type*a(i_a)%num_hbond_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%num_hbond_n_type
          do i2=1, a(i_a)%num_hbond_n_bins
            !call print(""//a(i_a)%num_hbond_type_code(i1)//" "//a(i_a)%num_hbond_bin_pos(i2), file=outfile)
            call print(""//trim(a(i_a)%num_hbond_type_label(i1))//" "//a(i_a)%num_hbond_bin_pos(i2), file=outfile)
          end do
        end do
        !histograms
        do i=1, a(i_a)%n_configs
          call print(""//reshape(a(i_a)%num_hbond_histograms(:,:,i), (/ a(i_a)%num_hbond_n_type*a(i_a)%num_hbond_n_bins /) ), file=outfile)
        end do

        !integrated histograms header
        call print("", file=outfile)
        call print("", file=outfile)
        call print("# integrated_num_hbond_silica", file=outfile)
        call print("n_bins="//a(i_a)%num_hbond_n_type*a(i_a)%num_hbond_n_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%num_hbond_n_type
          do i2=1, a(i_a)%num_hbond_n_bins
            !call print(""//a(i_a)%num_hbond_type_code(i1)//" "//a(i_a)%num_hbond_bin_pos(i2), file=outfile)
            call print(""//trim(a(i_a)%num_hbond_type_label(i1))//" "//a(i_a)%num_hbond_bin_pos(i2), file=outfile)
          end do
        end do
        !integrated histograms
	allocate(a(i_a)%integrated_num_hbond_histograms(a(i_a)%num_hbond_n_bins,a(i_a)%num_hbond_n_type))
	a(i_a)%integrated_num_hbond_histograms = 0.0_dp
        do i=1, a(i_a)%n_configs
	  a(i_a)%integrated_num_hbond_histograms = 0.0_dp
	  do i1=1, a(i_a)%num_hbond_n_type
	    do i2=2, a(i_a)%num_hbond_n_bins
	      a(i_a)%integrated_num_hbond_histograms(i2,i1) = a(i_a)%integrated_num_hbond_histograms(i2-1,i1) + &
		(a(i_a)%num_hbond_bin_pos(i2)-a(i_a)%num_hbond_bin_pos(i2-1))* &
		4.0_dp*PI*((a(i_a)%num_hbond_bin_pos(i2)**2)*a(i_a)%num_hbond_histograms(i2,i1,i)+(a(i_a)%num_hbond_bin_pos(i2-1)**2)*a(i_a)%num_hbond_histograms(i2-1,i1,i))/2.0_dp
	    end do
	  end do
          call print(""//reshape(a(i_a)%integrated_num_hbond_histograms(:,:), (/ a(i_a)%num_hbond_n_type*a(i_a)%num_hbond_n_bins /) ), file=outfile)
        end do
	deallocate(a(i_a)%integrated_num_hbond_histograms)

      else if (a(i_a)%water_orientation_silica) then !water_orientation_silica
        !header
        call print("# water_orientation_silica in direction "//a(i_a)%water_orientation_axis, file=outfile)
        call print("n_bins="//a(i_a)%water_orientation_n_pos_bins*a(i_a)%water_orientation_n_angle_bins//" n_data="//a(i_a)%n_configs, file=outfile)
        do i1=1, a(i_a)%water_orientation_n_pos_bins
          do i2=1, a(i_a)%water_orientation_n_angle_bins
            call print(""//a(i_a)%water_orientation_pos_bin(i1)//" "//a(i_a)%water_orientation_angle_bin(i2), file=outfile)
          end do
        end do
        !histograms
        do i=1, a(i_a)%n_configs
          call print(""//reshape(a(i_a)%water_orientation_histograms(:,:,i), (/ a(i_a)%water_orientation_n_pos_bins*a(i_a)%water_orientation_n_angle_bins /) ), file=outfile)
        end do

      else
        call system_abort("print_analyses: no type of analysis set for " // i_a)
      endif
    endif
    call finalise(outfile)
  end do
end subroutine print_analyses

subroutine density_sample_radial_mesh_Gaussians(histogram, at, center_pos, center_i, rad_bin_width, n_rad_bins, gaussian_sigma, mask_str, radial_pos, accumulate)
  real(dp), intent(inout) :: histogram(:)
  type(Atoms), intent(inout) :: at
  real(dp), intent(in), optional :: center_pos(3)
  integer, intent(in), optional :: center_i
  real(dp), intent(in) :: rad_bin_width
  integer, intent(in) :: n_rad_bins
  real(dp), intent(in) :: gaussian_sigma
  character(len=*), optional, intent(in) :: mask_str
  real(dp), intent(out), optional :: radial_pos(:)
  logical, optional, intent(in) :: accumulate

  logical :: my_accumulate

  real(dp) :: use_center_pos(3), d, r0, s_sq
  real(dp), parameter :: SQROOT_PI = sqrt(PI)
  logical, allocatable :: mask_a(:)
  integer :: at_i, rad_sample_i
  real(dp) :: rad_sample_r, exp_arg, ep, em

  if (present(center_pos) .and. present(center_i)) &
    call system_abort("density_sample_radial_mesh_Gaussians got both center_pos and center_i")
  if (.not. present(center_pos) .and. .not. present(center_i)) &
    call system_abort("density_sample_radial_mesh_Gaussians got neither center_pos nor center_i")

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  allocate(mask_a(at%N))
  call is_in_mask(mask_a, at, mask_str)

  if (present(radial_pos)) then
    do rad_sample_i=1, n_rad_bins
      rad_sample_r = (rad_sample_i-1)*rad_bin_width
      radial_pos(rad_sample_i) = rad_sample_r
    end do
  endif

  ! ratio of 20/4=5 is bad
  ! ratio of 20/3=6.66 is bad
  ! ratio of 20/2.5=8 is borderline (2e-4)
  ! ratio of 20/2.22=9 is fine  (error 2e-5)
  ! ratio of 20/2=10 is definitely fine
  if (min(norm(at%lattice(:,1)), norm(at%lattice(:,2)), norm(at%lattice(:,3))) < 9.0_dp*gaussian_sigma) &
    call print("WARNING: at%lattice may be too small for sigma, errors (noticeably too low a density) may result", ERROR)

  if (present(center_pos)) then
    use_center_pos = center_pos
  else
    use_center_pos = at%pos(:,center_i)
  end if

  s_sq = gaussian_sigma**2
  do at_i=1, at%N
    if (.not. mask_a(at_i)) cycle
    d = distance_min_image(at,use_center_pos,at%pos(:,at_i))
    do rad_sample_i=1, n_rad_bins
      rad_sample_r = (rad_sample_i-1)*rad_bin_width
      r0 = rad_sample_r
      ep = 0.0_dp
      exp_arg = -(r0+d)**2/s_sq
      if (exp_arg > -20.0_dp) ep = exp(exp_arg)
      em = 0.0_dp
      exp_arg = -(r0-d)**2/s_sq
      if (exp_arg > -20.0_dp) em = exp(exp_arg)
      ! should really fix d->0 limit
      if (d .fne. 0.0_dp) &
	histogram(rad_sample_i) = histogram(rad_sample_i) + r0/(SQROOT_PI * gaussian_sigma * d) * (em - ep)
    end do ! rad_sample_i
  end do ! at_i

  do rad_sample_i=1, n_rad_bins
    rad_sample_r = (rad_sample_i-1)*rad_bin_width
    if (rad_sample_r > 0.0_dp) &
      histogram(rad_sample_i) = histogram(rad_sample_i) / (4.0_dp * pi * rad_sample_r**2)
  end do

end subroutine density_sample_radial_mesh_Gaussians

subroutine rdfd_calc(rdfd, at, zone_center, bin_width, n_bins, zone_width, n_zones, gaussian_smoothing, gaussian_sigma, &
                     center_mask_str, neighbour_mask_str, bin_pos, zone_pos)
  real(dp), intent(inout) :: rdfd(:,:)
  type(Atoms), intent(inout) :: at
  real(dp), intent(in) :: zone_center(3), bin_width, zone_width
  integer, intent(in) :: n_bins, n_zones
  logical, intent(in) :: gaussian_smoothing
  real(dp), intent(in) :: gaussian_sigma
  character(len=*), intent(in) :: center_mask_str, neighbour_mask_str
  real(dp), intent(inout), optional :: bin_pos(:), zone_pos(:)

  logical, allocatable :: center_mask_a(:), neighbour_mask_a(:)
  integer :: i_at, j_at, i_bin, i_zone
  integer, allocatable :: n_in_zone(:)
  real(dp) :: r, bin_inner_rad, bin_outer_rad

  allocate(center_mask_a(at%N))
  allocate(neighbour_mask_a(at%N))
  call is_in_mask(center_mask_a, at, center_mask_str)
  call is_in_mask(neighbour_mask_a, at, neighbour_mask_str)

  allocate(n_in_zone(n_zones))
  n_in_zone = 0

  if (present(zone_pos)) then
    if (zone_width > 0.0_dp) then
      do i_zone=1, n_zones
        zone_pos(i_zone) = (real(i_zone,dp)-0.5_dp)*zone_width
      end do
    else
      zone_pos(1) = -1.0_dp
    endif
  endif
  if (present(bin_pos)) then
    do i_bin=1, n_bins
      if (gaussian_smoothing) then
        bin_pos(i_bin) = (i_bin-1)*bin_width
      else
        bin_pos(i_bin) = (real(i_bin,dp)-0.5_dp)*bin_width
      endif
    end do
  endif

  if (gaussian_smoothing) then
    call set_cutoff(at, n_bins*bin_width+5.0_dp*gaussian_sigma)
    call calc_connect(at)
  endif

  rdfd = 0.0_dp
  do i_at=1, at%N ! loop over center atoms
    if (.not. center_mask_a(i_at)) cycle

    !calc which zone the atom is in
    if (zone_width > 0.0_dp) then
      r = distance_min_image(at, zone_center, at%pos(:,i_at))
      i_zone = int(r/zone_width)+1
      if (i_zone > n_zones) cycle
    else
      i_zone = 1
    endif

    !count the number of atoms in that zone
    n_in_zone(i_zone) = n_in_zone(i_zone) + 1

    !calc rdfd in each bin for this zone
    if (gaussian_smoothing) then
      call density_sample_radial_mesh_Gaussians(rdfd(:,i_zone), at, center_i=i_at, rad_bin_width=bin_width, n_rad_bins=n_bins, &
        gaussian_sigma=gaussian_sigma, mask_str=neighbour_mask_str, accumulate = .true.)
    else
      !loop over atoms and advance the bins
      do j_at=1, at%N
        if (j_at == i_at) cycle
        if (.not. neighbour_mask_a(j_at)) cycle
        r = distance_min_image(at, i_at, j_at)
        i_bin = int(r/bin_width)+1
        if (i_bin <= n_bins) rdfd(i_bin,i_zone) = rdfd(i_bin,i_zone) + 1.0_dp
      end do ! j_at
    endif ! gaussian_smoothing
  end do ! i_at

  !normalise zones by the number of atoms in that zone
  do i_zone=1, n_zones
    if (n_in_zone(i_zone) > 0) rdfd(:,i_zone) = rdfd(:,i_zone)/real(n_in_zone(i_zone),dp)
  end do

  !calculate local density by dividing bins with their volumes
  if (.not. gaussian_smoothing) then
    do i_bin=1, n_bins
      bin_inner_rad = real(i_bin-1,dp)*bin_width
      bin_outer_rad = real(i_bin,dp)*bin_width
      rdfd(i_bin,:) = rdfd(i_bin,:)/(4.0_dp/3.0_dp*PI*bin_outer_rad**3 - 4.0_dp/3.0_dp*PI*bin_inner_rad**3)
    end do
  endif
  !normalizing with the global density
  if (count(neighbour_mask_a) > 0) then
    rdfd = rdfd / (count(neighbour_mask_a)/cell_volume(at))
  endif

end subroutine rdfd_calc

subroutine density_sample_rectilinear_mesh_Gaussians(histogram, at, min_p, sample_dist, n_bins, gaussian_sigma, mask_str, grid_pos, accumulate)
  real(dp), intent(inout) :: histogram(:,:,:)
  type(Atoms), intent(in) :: at
  real(dp), intent(in) :: min_p(3), sample_dist(3)
  integer, intent(in) :: n_bins(3)
  real(dp), intent(in) :: gaussian_sigma
  character(len=*), optional, intent(in) :: mask_str
  real(dp), intent(out), optional :: grid_pos(:,:,:,:)
  logical, optional, intent(in) :: accumulate

  logical :: my_accumulate
  integer :: at_i, i1, i2, i3
  real(dp) :: p(3), w, dist
  logical, allocatable :: mask_a(:)

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  allocate(mask_a(at%N))
  call is_in_mask(mask_a, at, mask_str)

! ratio of 20/4=5 is bad
! ratio of 20/3=6.66 is bad
! ratio of 20/2.5=8 is borderline (2e-4)
! ratio of 20/2.22=9 is fine  (error 2e-5)
! ratio of 20/2=10 is fine
  if ( (norm(at%lattice(:,1)) < 9.0_dp*gaussian_sigma) .or. &
       (norm(at%lattice(:,2)) < 9.0_dp*gaussian_sigma) .or. &
       (norm(at%lattice(:,3)) < 9.0_dp*gaussian_sigma) ) &
    call print("WARNING: at%lattice may be too small for sigma, errors (noticeably too low a density) may result", ERROR)

  w = 1.0_dp / (gaussian_sigma*sqrt(2.0_dp*PI))**3

  if (present(grid_pos)) then
    do i1=1, n_bins(1)
      p(1) = min_p(1) + (i1-1)*sample_dist(1)
      do i2=1, n_bins(2)
        p(2) = min_p(2) + (i2-1)*sample_dist(2)
        do i3=1, n_bins(3)
          p(3) = min_p(3) + (i3-1)*sample_dist(3)
          grid_pos(:,i1,i2,i3) = p
        end do
      end do
    end do
  endif

  do at_i=1, at%N
    if (.not. mask_a(at_i)) cycle
    do i1=1, n_bins(1)
      p(1) = min_p(1) + (i1-1)*sample_dist(1)
      do i2=1, n_bins(2)
        p(2) = min_p(2) + (i2-1)*sample_dist(2)
        do i3=1, n_bins(3)
          p(3) = min_p(3) + (i3-1)*sample_dist(3)
          dist = distance_min_image(at,p,at%pos(:,at_i))
          histogram(i1,i2,i3) = histogram(i1,i2,i3) + exp(-0.5_dp*(dist/(gaussian_sigma))**2)*w
        end do ! i3
      end do ! i2
    end do ! i1
  end do ! at_i

  deallocate(mask_a)
end subroutine density_sample_rectilinear_mesh_Gaussians

subroutine density_bin_rectilinear_mesh(histogram, at, min_p, bin_width, n_bins, mask_str, grid_pos, accumulate)
  real(dp), intent(inout) :: histogram(:,:,:)
  type(Atoms), intent(in) :: at
  real(dp), intent(in) :: min_p(3), bin_width(3)
  integer, intent(in) :: n_bins(3)
  character(len=*), optional, intent(in) :: mask_str
  real(dp), intent(out), optional :: grid_pos(:,:,:,:)
  logical, optional, intent(in) :: accumulate

  logical :: my_accumulate
  integer :: i, i1, i2, i3, bin(3)
  logical, allocatable :: mask_a(:)
  real(dp) :: p(3)

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  if (present(grid_pos)) then
    do i1=1, n_bins(1)
      p(1) = min_p(1) + (real(i1,dp)-0.5_dp)*bin_width(1)
      do i2=1, n_bins(2)
        p(2) = min_p(2) + (real(i2,dp)-0.5_dp)*bin_width(2)
        do i3=1, n_bins(3)
          p(3) = min_p(3) + (real(i3,dp)-0.5_dp)*bin_width(3)
          grid_pos(:,i1,i2,i3) = p
        end do
      end do
    end do
  endif

  allocate(mask_a(at%N))
  call is_in_mask(mask_a, at, mask_str)

  do i=1, at%N
    if (.not. mask_a(i)) cycle
    bin = floor((at%pos(:,i)-min_p)/bin_width)+1
    if (all(bin >= 1) .and. all (bin <= n_bins)) histogram(bin(1),bin(2),bin(3)) = histogram(bin(1),bin(2),bin(3)) + 1.0_dp
  end do

  deallocate(mask_a)

end subroutine density_bin_rectilinear_mesh

subroutine is_in_mask(mask_a, at, mask_str)
  type(Atoms), intent(in) :: at
  logical, intent(out) :: mask_a(at%N)
  character(len=*), optional, intent(in) :: mask_str

  integer :: i_at, i_Z
  integer :: Zmask
  type(Table) :: atom_indices
  character(len=4) :: species(128)
  integer :: n_species

  if (.not. present(mask_str)) then
    mask_a = .true.
    return
  endif

  if (len_trim(mask_str) == 0) then
    mask_a = .true.
    return
  endif

  mask_a = .false.
  if (mask_str(1:1)=='@') then
    call parse_atom_mask(mask_str,atom_indices)
    do i_at=1, atom_indices%N
      mask_a(atom_indices%int(1,i_at)) = .true.
    end do
  else if (scan(mask_str,'=')/=0) then
    call system_abort("property type mask not supported yet")
  else
    call split_string(mask_str, ' ,', '""', species, n_species)
    do i_Z=1, n_species
      Zmask = Atomic_Number(species(i_Z))
      do i_at=1, at%N
        if (at%Z(i_at) == Zmask) mask_a(i_at) = .true.
      end do
    end do
  end if
end subroutine is_in_mask

subroutine reallocate_data_1d(data, n, n_bins)
  real(dp), allocatable, intent(inout) :: data(:,:)
  integer, intent(in) :: n, n_bins

  integer :: new_size
  real(dp), allocatable :: t_data(:,:)

  if (allocated(data)) then
    if (n <= size(data,2)) return
    allocate(t_data(size(data,1),size(data,2)))
    t_data = data
    deallocate(data)
    if (size(t_data,2) <= 0) then
      new_size = 10
    else if (size(t_data,2) < 1000) then
      new_size = 2*size(t_data,2)
    else
      new_size = floor(1.25*size(t_data,2))
    endif
    allocate(data(size(t_data,1), new_size))
    data(1:size(t_data,1),1:size(t_data,2)) = t_data(1:size(t_data,1),1:size(t_data,2))
    data(1:size(t_data,1),size(t_data,2)+1:size(data,2)) = 0.0_dp
    deallocate(t_data)
  else
    allocate(data(n_bins, n))
  endif
end subroutine reallocate_data_1d

subroutine reallocate_data_2d(data, n, n_bins)
  real(dp), allocatable, intent(inout) :: data(:,:,:)
  integer, intent(in) :: n, n_bins(2)
 
  integer :: new_size
  real(dp), allocatable :: t_data(:,:,:)

  if (allocated(data)) then
    if (n <= size(data,3)) return
    allocate(t_data(size(data,1),size(data,2),size(data,3)))
    t_data = data
    deallocate(data)
    if (size(t_data,3) <= 0) then
      new_size = 10
    else if (size(t_data,3) < 1000) then
      new_size = 2*size(t_data,3)
    else
      new_size = floor(1.25*size(t_data,3))
    endif
    allocate(data(size(t_data,1), size(t_data,2), new_size))
    data(1:size(t_data,1),1:size(t_data,2),1:size(t_data,3)) = &
      t_data(1:size(t_data,1),1:size(t_data,2),1:size(t_data,3))
    data(1:size(t_data,1),1:size(t_data,2),size(t_data,3)+1:size(data,3)) = 0.0_dp
    deallocate(t_data)
  else
    allocate(data(n_bins(1), n_bins(2), n))
  endif
end subroutine reallocate_data_2d

subroutine reallocate_data_3d(data, n, n_bins)
  real(dp), allocatable, intent(inout) :: data(:,:,:,:)
  integer, intent(in) :: n, n_bins(3)

  integer :: new_size
  real(dp), allocatable :: t_data(:,:,:,:)

  if (allocated(data)) then
    if (n <= size(data,4)) return
    allocate(t_data(size(data,1),size(data,2),size(data,3),size(data,4)))
    t_data = data
    deallocate(data)
    if (size(t_data,4) <= 0) then
      new_size = 10
    else if (size(t_data,4) < 1000) then
      new_size = 2*size(t_data,4)
    else
      new_size = floor(1.25*size(t_data,4))
    endif
    allocate(data(size(t_data,1), size(t_data,2), size(t_data,3), new_size))
    data(1:size(t_data,1),1:size(t_data,2),1:size(t_data,3),1:size(t_data,4)) = &
      t_data(1:size(t_data,1),1:size(t_data,2),1:size(t_data,3),1:size(t_data,4))
    data(1:size(t_data,1),1:size(t_data,2),1:size(t_data,3),size(t_data,4)+1:size(data,4)) = 0.0_dp
    deallocate(t_data)
  else
    allocate(data(n_bins(1), n_bins(2), n_bins(3), n))
  endif
end subroutine reallocate_data_3d

!read geometry parameters to calculate
!format:
!4               number of params
!anything        comment
!1 3             type #1: y-coord  of atom  #3
!2 4 5           type #2: distance of atoms #4--#5
!3 3 4 5         type #3: angle    of atoms #3--#4--#5
!4 3 1 2 4       type #4: dihedral of atoms #3--#1--#2--#4
subroutine read_geometry_params(this,filename)

  type(analysis), intent(inout) :: this
  character(*), intent(in) :: filename

  type(inoutput) :: geom_lib
  character(20), dimension(10) :: fields
  integer :: num_fields, status
  integer :: num_geom, i, geom_type
  character(FIELD_LENGTH) :: comment

  call initialise(this%geometry_params,5,0,0,0,0) !type, atom1, atom2, atom3, atom4

  if (trim(filename)=="") then
     call print('WARNING! no file specified')
     return !with an empty table
  endif

  call initialise(geom_lib,trim(filename),action=INPUT)
  call parse_line(geom_lib,' ',fields,num_fields)
  if (num_fields < 1) then
     call print ('WARNING! empty file '//trim(filename))
     call finalise(geom_lib)
     return !with an empty table
  endif

  num_geom = string_to_int(fields(1))
  comment=""
  comment = read_line(geom_lib,status)
  call print(trim(comment),VERBOSE)

  do i=1,num_geom
    call parse_line(geom_lib,' ',fields,num_fields)
    if (num_fields.gt.5 .or. num_fields.lt.2) call system_abort('read_geometry_params: 1 type and maximum 4 atoms must be in the geometry file')
    geom_type = string_to_int(fields(1))
    select case (geom_type)
      case (1) !y coord atom1
        if (num_fields.lt.2) call system_abort('type 1: coordinate, =1 atom needed')
        call append(this%geometry_params,(/geom_type, &
                                           string_to_int(fields(2)), &
                                           0, &
                                           0, &
                                           0/) )
      case (2) !distance atom1-atom2
        if (num_fields.lt.3) call system_abort('type 2: bond length, =2 atom needed')
        call append(this%geometry_params, (/geom_type, &
                                            string_to_int(fields(2)), &
                                            string_to_int(fields(3)), &
                                            0, &
                                            0/) )
      case (3) !angle atom1-atom2-atom3
        if (num_fields.lt.4) call system_abort('type 3: angle, =3 atom needed')
        call append(this%geometry_params, (/geom_type, &
                                            string_to_int(fields(2)), &
                                            string_to_int(fields(3)), &
                                            string_to_int(fields(4)), &
                                            0/) )
      case (4) !dihedral atom1-atom2-atom3-atom4
        if (num_fields.lt.5) call system_abort('type 4: dihedral, =4 atom needed')
        call append(this%geometry_params, (/geom_type, &
                                            string_to_int(fields(2)), &
                                            string_to_int(fields(3)), &
                                            string_to_int(fields(4)), &
                                            string_to_int(fields(5)) /) )
      case default
        call system_abort('unknown type '//geom_type//', must be one of 1(y coordinate), 2(bond length/distance), 3(angle), 4(dihedral).')
    end select
  enddo

  call finalise(geom_lib)

end subroutine read_geometry_params

!Calculates distances, angles, dihedrals of the given atoms
subroutine geometry_calc(histogram, at, geometry_params, central_atom, geometry_pos, geometry_label)

  real(dp), intent(inout) :: histogram(:)
  type(Atoms), intent(inout) :: at
  type(Table), intent(in) :: geometry_params
  integer, intent(in) :: central_atom
  real(dp), intent(out), optional :: geometry_pos(:)
  character(FIELD_LENGTH), intent(out), optional :: geometry_label(:)

  integer :: i, j, geom_type
  integer :: atom1, atom2, atom3, atom4
  real(dp) :: shift(3), bond12(3),bond23(3),bond34(3)

  !center around central_atom if requested
  if (central_atom.gt.at%N) call system_abort('central atom is greater than atom number '//at%N)
  if (central_atom.gt.0) then !center around central_atom
     shift = at%pos(1:3,central_atom)
     do j=1,at%N
        at%pos(1:3,j) = at%pos(1:3,j) - shift(1:3)
     enddo
     call map_into_cell(at) !only in this case, otherwise it has been mapped
  endif

  !loop over the parameters to calculate
  do i=1, geometry_params%N
     geom_type=geometry_params%int(1,i)
     atom1 = geometry_params%int(2,i)
     atom2 = geometry_params%int(3,i)
     atom3 = geometry_params%int(4,i)
     atom4 = geometry_params%int(5,i)
     select case (geom_type)
       case(1) !y coord atom1
         if (atom1<1.or.atom1>at%N) call system_abort('atom1 must be >0 and < '//at%N)
         histogram(i) = at%pos(2,atom1)
       case(2) !distance atom1-atom2
         if (atom1<1.or.atom1>at%N) call system_abort('atom1 must be >0 and < '//at%N)
         if (atom2<1.or.atom2>at%N) call system_abort('atom2 must be >0 and < '//at%N)
         !histogram(i) = norm(at%pos(1:3,atom1)-at%pos(1:3,atom2))
         histogram(i) = distance_min_image(at,atom1,atom2)
       case(3) !angle atom1-atom2-atom3
         if (atom1<1.or.atom1>at%N) call system_abort('atom1 must be >0 and < '//at%N)
         if (atom2<1.or.atom2>at%N) call system_abort('atom2 must be >0 and < '//at%N)
         if (atom3<1.or.atom2>at%N) call system_abort('atom3 must be >0 and < '//at%N)
         !histogram(i) = angle(at%pos(1:3,atom1)-at%pos(1:3,atom2), &
         !                     at%pos(1:3,atom3)-at%pos(1:3,atom2))
         histogram(i) = angle(diff_min_image(at,atom2,atom1), &
                              diff_min_image(at,atom2,atom3))
       case(4) !dihedral atom1-(bond12)->atom2-(bond23)->atom3-(bond34)->atom4
         if (atom1<1.or.atom1>at%N) call system_abort('atom1 must be >0 and < '//at%N)
         if (atom2<1.or.atom2>at%N) call system_abort('atom2 must be >0 and < '//at%N)
         if (atom3<1.or.atom2>at%N) call system_abort('atom3 must be >0 and < '//at%N)
         if (atom4<1.or.atom2>at%N) call system_abort('atom4 must be >0 and < '//at%N)
         !bond12(1:3) = at%pos(1:3,atom2)-at%pos(1:3,atom1)
         bond12(1:3) = diff_min_image(at,atom1,atom2)
         !bond23(1:3) = at%pos(1:3,atom3)-at%pos(1:3,atom2)
         bond23(1:3) = diff_min_image(at,atom2,atom3)
         !bond34(1:3) = at%pos(1:3,atom4)-at%pos(1:3,atom3)
         bond34(1:3) = diff_min_image(at,atom3,atom4)
         histogram(i) = atan2(norm(bond23(1:3)) * bond12(1:3).dot.(bond23(1:3).cross.bond34(1:3)), &
                              (bond12(1:3).cross.bond23(1:3)) .dot. (bond23(1:3).cross.bond34(1:3)))
       case default
         call system_abort("geometry_calc: unknown geometry type "//geom_type)
     end select
     if (present(geometry_pos)) geometry_pos(i) = real(i,dp)
     if (present(geometry_label)) geometry_label(i) = geom_type//'=='//atom1//'--'//atom2//'--'//atom3//'--'//atom4
  enddo

end subroutine geometry_calc


!silica-water inerface: put half-half of the silica slab to the 2 edges of the cell along the axis  normal to the surface
subroutine shift_silica_to_edges(at, axis, silica_center_i, mask_str)
  type(Atoms), intent(inout) :: at
  integer, intent(in) :: axis
  integer, intent(in) :: silica_center_i
  character(len=*), optional, intent(in) :: mask_str

  logical, allocatable :: mask_a(:), mask_silica(:)
  integer :: i
  integer :: counter
  integer, allocatable :: Si_atoms(:)
  real(dp) :: com(3), shift(3)
  real(dp), pointer :: mass_p(:)

  if (.not.silica_center_i>0) return

  !find the com of the silica (using the Si atoms) and move that to the edges in this direction
  shift(1:3) = at%pos(1:3,1)
  do i=1,at%N
     at%pos(1:3,i) = at%pos(1:3,i) - shift(1:3)
  enddo
  call map_into_cell(at)
  allocate(mask_silica(at%N))
  call is_in_mask(mask_silica, at, "Si")
  allocate(Si_atoms(count(mask_silica)))
  counter = 0
  do i=1,at%N
     if (mask_silica(i)) then
        counter = counter + 1
        Si_atoms(counter) = i
     endif
  enddo
  !allocate(at%mass(at%N))
  !at%mass = ElementMass(at%Z)
  call add_property(at,"mass",0._dp)
  if (.not.(assign_pointer(at, "mass", mass_p))) call system_abort('??')
  mass_p = ElementMass(at%Z)
  com = centre_of_mass(at,index_list=Si_atoms(1:size(Si_atoms)),origin=1)
  !shift axis to the edge (-0.5*edge_length)
  at%pos(axis,1:at%N) = at%pos(axis,1:at%N) - 0.5_dp * at%lattice(axis,axis) - com(axis)
  call map_into_cell(at) !everyone becomes -0.5b<y<0.5b
  !NO !shift everyone to positive coordinate along axis
  !at%pos(axis,1:at%N) = at%pos(axis,1:at%N) + 0.5_dp * at%lattice(axis,axis)
  deallocate(Si_atoms)
  deallocate(mask_silica)

end subroutine shift_silica_to_edges

subroutine density_axial_calc(histogram, at, axis, silica_center_i,n_bins, gaussian_smoothing, gaussian_sigma, mask_str, axial_pos, accumulate)
  real(dp), intent(inout) :: histogram(:)
  type(Atoms), intent(inout) :: at
  integer, intent(in) :: axis
  integer, intent(in) :: silica_center_i
  integer, intent(in) :: n_bins
  logical, intent(in) :: gaussian_smoothing
  real(dp), intent(in) :: gaussian_sigma
  character(len=*), optional, intent(in) :: mask_str
  real(dp), intent(out), optional :: axial_pos(:)
  logical, optional, intent(in) :: accumulate

  logical :: my_accumulate
  real(dp) :: ax_sample_r, dist, r, exp_arg
  logical, allocatable :: mask_a(:)
  integer at_i, ax_sample_i, i
  real(dp) :: bin_width

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  !atommask
  allocate(mask_a(at%N))
  call is_in_mask(mask_a, at, mask_str)

  !bin labels
  bin_width = at%lattice(axis,axis) / n_bins
  if (present(axial_pos)) then
    do ax_sample_i=1, n_bins
      ax_sample_r = (real(ax_sample_i,dp)-0.5_dp)*bin_width !the middle of the bin
      axial_pos(ax_sample_i) = ax_sample_r
    end do
  endif

  if (silica_center_i>0) then ! silica
     call shift_silica_to_edges(at, axis, silica_center_i, mask_str)
  endif

  !now bins are from -axis/2 to axis/2
  !shift everyone to positive coordinate along axis
  at%pos(axis,1:at%N) = at%pos(axis,1:at%N) + 0.5_dp * at%lattice(axis,axis)


  !simply check distances and bin them


  ! ratio of 20/4=5 is bad
  ! ratio of 20/3=6.66 is bad
  ! ratio of 20/2.5=8 is borderline (2e-4)
  ! ratio of 20/2.22=9 is fine  (error 2e-5)
  ! ratio of 20/2=10 is fine
  if ( gaussian_smoothing .and. (at%lattice(axis,axis) < 9.0_dp*gaussian_sigma) ) &
    call print("WARNING: at%lattice may be too small for sigma, errors (noticeably too low a density) may result", ERROR)

  if (gaussian_smoothing) then

    do at_i=1, at%N
      if (silica_center_i>0 .and. at_i<=silica_center_i) cycle !ignore silica atoms
      if (.not. mask_a(at_i)) cycle
      r = at%pos(axis,at_i)
      do ax_sample_i=1, n_bins

        ax_sample_r = (real(ax_sample_i,dp)-0.5_dp)*bin_width
        dist = abs(r - ax_sample_r)
!Include all the atoms, slow but minimises error
!	  if (dist > 4.0_dp*gaussian_sigma) cycle
          exp_arg = -0.5_dp*(dist/(gaussian_sigma))**2
          if (exp_arg > -20.0_dp) then ! good to about 1e-8
            histogram(ax_sample_i) = histogram(ax_sample_i) + exp(exp_arg)/(gaussian_sigma*sqrt(2.0_dp*PI)) !Gaussian in 1 dimension
          endif

      end do ! ax_sample_i
    end do ! at_i

  else !no gaussian_smoothing

    do at_i=1, at%N
      if (silica_center_i>0 .and. at_i<=silica_center_i) cycle !ignore silica atoms
      if (.not. mask_a(at_i)) cycle
      r = at%pos(axis,at_i)

        histogram(int(r/bin_width)+1) = histogram(int(r/bin_width)+1) + 1

    end do ! at_i

  endif

  deallocate(mask_a)
end subroutine density_axial_calc

!
! Calculates the number of H-bonds along an axis
!  -- 1st center around atom 1
!  -- then calculate COM of Si atoms
!  -- then shift the centre of mass along the y axis to y=0
!  -- calculate H bonds for
!        water - water
!        water - silica
!        silica - water
!        silica - silica
!     interactions
!  -- the definition of a H-bond (O1-H1 - - O2):
!        d(O1,O2) < 3.5 A
!        d(O2,H1) < 2.45 A
!        angle(H1,O1,O2) < 30 degrees
!     source: P. Jedlovszky, J.P. Brodholdt, F. Bruni, M.A. Ricci and R. Vallauri, J. Chem. Phys. 108, 8525 (1998)
!
subroutine num_hbond_calc(histogram, at, axis, silica_center_i,n_bins, gaussian_smoothing, gaussian_sigma, mask_str, num_hbond_pos, num_hbond_type_code, num_hbond_type_label,accumulate)
  real(dp),                          intent(inout) :: histogram(:,:)
  type(Atoms),                       intent(inout) :: at
  integer,                           intent(in)    :: axis
  integer,                           intent(in)    :: silica_center_i
  integer,                           intent(in)    :: n_bins
  logical,                           intent(in)    :: gaussian_smoothing
  real(dp),                          intent(in)    :: gaussian_sigma
  character(len=*),        optional, intent(in)    :: mask_str
  real(dp),                optional, intent(out)   :: num_hbond_pos(:)
  integer,                 optional, intent(out)   :: num_hbond_type_code(:)
  character(FIELD_LENGTH), optional, intent(out)   :: num_hbond_type_label(:)
  logical,                 optional, intent(in)    :: accumulate

  logical :: my_accumulate
  real(dp) :: num_hbond_sample_r, dist, r, exp_arg
  logical, allocatable :: mask_a(:)
  integer :: num_hbond_sample_i
  real(dp) :: bin_width
  real(dp), parameter                   :: dist_O2_H1 = 2.45_dp
  real(dp), parameter                   :: dist_O1_O2 = 3.5_dp
  real(dp), parameter                   :: angle_H1_O1_O2 = 30._dp
real(dp) :: min_distance, distance, HOO_angle
integer :: H1, O1, i, j, k, O2, num_atoms, hbond_type

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  !atommask
  allocate(mask_a(at%N))
  call is_in_mask(mask_a, at, mask_str)

  !bin labels
  bin_width = at%lattice(axis,axis) / n_bins
  if (present(num_hbond_pos)) then
    do num_hbond_sample_i=1, n_bins
      num_hbond_sample_r = (real(num_hbond_sample_i,dp)-0.5_dp)*bin_width !the middle of the bin
      num_hbond_pos(num_hbond_sample_i) = num_hbond_sample_r
    end do
  endif
  if (present(num_hbond_type_label)) then
    num_hbond_type_label(1)="water-water"
    num_hbond_type_label(2)="water-silica"
    num_hbond_type_label(3)="silica-water"
    num_hbond_type_label(4)="silica-silica"
  endif
  if (present(num_hbond_type_code)) then
    num_hbond_type_code(1)=11
    num_hbond_type_code(2)=10
    num_hbond_type_code(3)=01
    num_hbond_type_code(4)=00
  endif

  if (silica_center_i>0) then ! silica
     call shift_silica_to_edges(at, axis, silica_center_i, mask_str)
  endif

  !!calc_connect now, before shifting positions to positive, because it would remap the positions!!
  !call calc_connect including the H-bonds
  call set_cutoff(at,dist_O2_H1)
  call calc_connect(at)

  !now bins are from -axis/2 to axis/2
  !shift everyone to positive coordinate along axis
  at%pos(axis,1:at%N) = at%pos(axis,1:at%N) + 0.5_dp * at%lattice(axis,axis)

  !simply check hbonds and bin them


  ! ratio of 20/4=5 is bad
  ! ratio of 20/3=6.66 is bad
  ! ratio of 20/2.5=8 is borderline (2e-4)
  ! ratio of 20/2.22=9 is fine  (error 2e-5)
  ! ratio of 20/2=10 is fine
  if ( gaussian_smoothing .and. (at%lattice(axis,axis) < 9.0_dp*gaussian_sigma) ) &
    call print("WARNING: at%lattice may be too small for sigma, errors (noticeably too low a density) may result", ERROR)

!  call set_cutoff(at,dist_O2_H1)
!  call calc_connect(at)

  num_atoms = 0
  do H1=1, at%N
     if(at%Z(H1)/=1) cycle !find H: H1
     !Count the atoms
     call print('Found H'//H1//ElementName(at%Z(H1)),ANAL)
     num_atoms = num_atoms + 1

     !find closest O: O1
     min_distance = huge(1._dp)
     O1 = 0
     k = 0
     do i = 1, atoms_n_neighbours(at,H1)
        j = atoms_neighbour(at,H1,i,distance)
        if (distance<min_distance) then
           min_distance = distance
           k = i  !the closest neighbour is the k-th one
           O1 = j
        endif
     enddo
     if (O1==0) call system_abort('H has no neighbours.')
     !if (at%Z(O1).ne.8) call system_abort('H'//H1//' has not O closest neighbour '//ElementName(at%Z(O1))//O1//'.')
     if (.not.mask_a(O1)) call system_abort('H'//H1//' has not O closest neighbour '//ElementName(at%Z(O1))//O1//'.')

     !loop over all other Os: O2
     do i = 1, atoms_n_neighbours(at,H1)
        if (i.eq.k) cycle
        O2 = atoms_neighbour(at,H1,i)
        !if (at%Z(O2).ne.8) cycle !only keep O
        if (.not. mask_a(O2)) cycle
        !check O1-O2 distance for definition
        if (distance_min_image(at,O1,O2).gt.dist_O1_O2) cycle
        !check H1-O1-O2 angle for definition
        HOO_angle = angle(diff_min_image(at,O1,H1), &
                          diff_min_image(at,O1,O2)) *180._dp/PI
        call print('HOO_ANGLE '//ElementName(at%Z(H1))//H1//' '//ElementName(at%Z(O1))//O1//' '//ElementName(at%Z(O2))//O2//' '//HOO_angle,ANAL)
        if (HOO_angle.gt.angle_H1_O1_O2) cycle

        !We've found a H-bond.

        !Find out the type (what-to-what)
        if (O1>silica_center_i .and. O2>silica_center_i) then  ! water - water
           call print('Found water-water H-bond.',ANAL)
           hbond_type = 1
        elseif (O1>silica_center_i .and. O2<=silica_center_i) then  ! water - silica
           call print('Found water-silica H-bond.',ANAL)
           hbond_type = 2
        elseif (O1<=silica_center_i .and. O2>silica_center_i) then  ! silica - water
           call print('Found silica-water H-bond.',ANAL)
           hbond_type = 3
        elseif (O1<=silica_center_i .and. O2<=silica_center_i) then  ! silica - silica
           call print('Found silica-silica H-bond.',ANAL)
           hbond_type = 4
        endif

        !Build histogram
        r = at%pos(axis,H1) !the position of H1

        if (gaussian_smoothing) then !smear the position along axis
           do num_hbond_sample_i=1, n_bins
             num_hbond_sample_r = (real(num_hbond_sample_i,dp)-0.5_dp)*bin_width
             dist = abs(r - num_hbond_sample_r)
!!!!!!Include all the atoms, slow but minimises error
!!!!!!	  if (dist > 4.0_dp*gaussian_sigma) cycle
               exp_arg = -0.5_dp*(dist/(gaussian_sigma))**2
               if (exp_arg > -20.0_dp) then ! good to about 1e-8
                 histogram(num_hbond_sample_i,hbond_type) = histogram(num_hbond_sample_i,hbond_type) + exp(exp_arg)/(gaussian_sigma*sqrt(2.0_dp*PI)) !Gaussian in 1 dimension
               endif
           end do ! num_hbond_sample_i
        else !no gaussian_smoothing
           histogram(int(r/bin_width)+1,hbond_type) = histogram(int(r/bin_width)+1,hbond_type) + 1
        endif
     end do ! i, atom_neighbours

  end do ! H1

  deallocate(mask_a)

end subroutine num_hbond_calc

!
! Calculates the orientation of water molecules along the y axis
!  -- 1st center around atom 1
!  -- then calculate COM of Si atoms
!  -- then shift the centre of mass along the y axis to y=0
!  -- calculate the orientation of the {dipole moment} / {angle half line} of the water: if skip_atoms is set to the last atom of the silica
!
subroutine water_orientation_calc(histogram, at, axis, silica_center_i,n_pos_bins, n_angle_bins, gaussian_smoothing, pos_gaussian_sigma, pos_bin, angle_bin, angle_bin_w, use_dipole_rather_than_angle_bisector, accumulate)
!subroutine water_orientation_calc(histogram, at, axis, silica_center_i,n_pos_bins, n_angle_bins, gaussian_smoothing, pos_gaussian_sigma, angle_gaussian_sigma, pos_bin, angle_bin, angle_bin_w, use_dipole_rather_than_angle_bisector, accumulate)
  real(dp),                          intent(inout) :: histogram(:,:)
  type(Atoms),                       intent(inout) :: at
  integer,                           intent(in)    :: axis
  integer,                           intent(in)    :: silica_center_i
  integer,                           intent(in)    :: n_pos_bins, n_angle_bins
  logical,                           intent(in)    :: gaussian_smoothing
  real(dp),                          intent(in)    :: pos_gaussian_sigma !, angle_gaussian_sigma
  real(dp),                optional, intent(out)   :: pos_bin(:), angle_bin(:)
  real(dp),                optional, intent(inout) :: angle_bin_w(:)
  logical,                 optional, intent(in)    :: use_dipole_rather_than_angle_bisector
  logical,                 optional, intent(in)    :: accumulate

  logical :: my_accumulate
  real(dp) :: sample_r, sample_angle, r
  logical, allocatable :: mask_a(:)
  integer :: sample_i
  real(dp) :: pos_bin_width, angle_bin_width
  real(dp) :: sum_w
integer :: n, num_atoms
integer :: O, H1, H2
  real(dp) :: surface_normal(3)
  logical :: use_dipole
real(dp) :: vector_OH1(3), vector_OH2(3)
real(dp) :: bisector_vector(3)
real(dp) :: dipole(3)
real(dp) :: orientation_angle
    real(dp), parameter                   :: charge_O = -0.834_dp
    real(dp), parameter                   :: charge_H = 0.417_dp
real(dp) :: sum_counts
real(dp) :: dist, exp_arg

  my_accumulate = optional_default(.false., accumulate)
  if (.not. my_accumulate) histogram = 0.0_dp

  use_dipole = optional_default(.true.,use_dipole_rather_than_angle_bisector)
  if (use_dipole) then
     call print("Using dipole to calculate angle with the surface normal.",VERBOSE)
  else
     call print("Using HOH angle bisector to calculate angle with the surface normal.",VERBOSE)
  endif

  !pos bin labels along axis
  pos_bin_width = at%lattice(axis,axis) / real(n_pos_bins,dp)
  if (present(pos_bin)) then
    do sample_i=1, n_pos_bins
      sample_r = (real(sample_i,dp)-0.5_dp)*pos_bin_width !the middle of the bin
      pos_bin(sample_i) = sample_r
    end do
  endif

 !angle bin labels
  angle_bin_width = PI/n_angle_bins
  if (present(pos_bin)) then
    sum_w = 0._dp
    do sample_i=1, n_angle_bins
      sample_angle = (real(sample_i,dp)-0.5_dp)*angle_bin_width !the middle of the bin
      angle_bin(sample_i) = sample_angle
      !the normalised solid angle is (1/4pi) * 2pi * sin((fi_north)-sin(fi_south)) where fi e [-pi/2,pi/2]
      angle_bin_w(sample_i) = 0.5_dp * ( sin(0.5_dp*PI - real(sample_i-1,dp)*angle_bin_width) - &
                                         sin(0.5_dp*PI - real(sample_i, dp)*angle_bin_width) )
      sum_w = sum_w + angle_bin_w(sample_i)
    end do
    angle_bin_w(1:n_angle_bins) = angle_bin_w(1:n_angle_bins) / sum_w
  endif

  !shift silica slab to the edges, water in the middle    || . . . ||
  if (silica_center_i>0) then ! silica
     call shift_silica_to_edges(at, axis, silica_center_i)
  endif

  !!calc_connect now, before shifting positions to positive, because it would remap the positions!!
  !call calc_connect including the H-bonds
  call set_cutoff(at,0._dp)
  call calc_connect(at)

  !now bins are from -axis/2 to axis/2
  !shift everyone to positive coordinate along axis
  at%pos(axis,1:at%N) = at%pos(axis,1:at%N) + 0.5_dp * at%lattice(axis,axis)

  !simply check water orientations and bin them


!  if (gaussian_smoothing) call system_abort('not implemented.')

  surface_normal(1:3) = 0._dp
  surface_normal(axis) = 1._dp

  num_atoms = 0
  do O=silica_center_i+1, at%N !only check water molecules
     if(at%Z(O)==1) cycle !find O
     !Count the atoms
     call print('Found O'//O//ElementName(at%Z(O)),ANAL)
     num_atoms = num_atoms + 1

     !find H neighbours
     n = atoms_n_neighbours(at,O)
     if (n.ne.2) then ! O with =2 nearest neighbours
        call print("WARNING! water(?) oxygen with "//n//"/=2 neighbours will be skipped!")
        cycle
     endif
     H1 = atoms_neighbour(at,O,1)
     H2 = atoms_neighbour(at,O,2)
     if ((at%Z(H1).ne.1).or.(at%Z(H2).ne.1)) then !2 H neighbours
        call print("WARNING! water(?) oxygen with non H neighbour will be skipped!")
        cycle
     endif
 
     !We've found a water molecule.

     !Build histogram
     r = at%pos(axis,H1) !the position of O
     !HOH_angle = angle(diff_min_image(at,O,H1), &
     !                  diff_min_image(at,O,H2)) !the H-O-H angle

     if (.not. use_dipole) then
     !VERSION 1.
     !the direction of the HH->O vector, the bisector of the HOH angle
     !vector that is compared to the surface normal:
     !  point from the bisector of the 2 Hs (scaled to have the same bond length)
     !        to the O
         vector_OH1(1:3) = diff_min_image(at, O, H1)
         if (norm(vector_OH1) > 1.2_dp) &
            call system_abort('too long OH bond? '//O//' '//H1//' '//norm(vector_OH1))
         vector_OH2(1:3) = diff_min_image(at, O, H2)
         if (norm(vector_OH2) > 1.2_dp) &
            call system_abort('too long OH bond? '//O//' '//H2//' '//norm(vector_OH1))
         bisector_vector(1:3) = vector_OH1(1:3) / norm(vector_OH1) * norm(vector_OH2)

         ! a.dot.b = |a|*|b|*cos(angle)
         orientation_angle = dot_product((bisector_vector(1:3)),surface_normal(1:3)) / &
                             sqrt(dot_product(bisector_vector(1:3),bisector_vector(1:3))) / &
                             sqrt(dot_product(surface_normal(1:3),surface_normal(1:3)))
     else ! use_dipole

     !VERSION 2.
     !the dipole of the water molecule = sum(q_i*r_i)
     !Calculate the dipole and its angle compared to the surface normal

         !
         dipole(1:3) = ( diff_min_image(at,O,H1)*charge_H + &
                         diff_min_image(at,O,H2)*charge_H )
         if (norm(diff_min_image(at,O,H1)).gt.1.2_dp) call system_abort('too long O-H1 bond (atoms '//O//'-'//H1//'): '//norm(diff_min_image(at,O,H1)))
         if (norm(diff_min_image(at,O,H2)).gt.1.2_dp) call system_abort('too long O-H2 bond (atoms '//O//'-'//H2//'): '//norm(diff_min_image(at,O,H2)))
!call print ('dipole '//dipole(1:3))
    
         ! a.dot.b = |a|*|b|*cos(angle)
         orientation_angle = dot_product((dipole(1:3)),surface_normal(1:3)) / &
                             sqrt(dot_product(dipole(1:3),dipole(1:3))) / &
                             sqrt(dot_product(surface_normal(1:3),surface_normal(1:3)))
     endif

     if (orientation_angle.gt.1._dp) then
        call print('WARNING | correcting cos(angle) to 1.0 = '//orientation_angle)
        orientation_angle = 1._dp
     else if (orientation_angle.lt.-1._dp) then
        call print('WARNING | correcting cos(angle) to -1.0 = '//orientation_angle)
        orientation_angle = -1._dp
     endif
     orientation_angle = acos(orientation_angle)
     if (orientation_angle.lt.0._dp) then
        call print('WARNING | correcting angle to 0.0: '//orientation_angle)
        orientation_angle = 0._dp
     endif
     if (orientation_angle.gt.PI) then
        call print('WARNING | correcting angle to pi : '//orientation_angle)
        orientation_angle = PI
     endif
!call print ('angle '//(orientation_angle*180._dp/pi))

     call print('Storing angle for water '//O//'--'//H1//'--'//H2//' with reference = '//round(orientation_angle,5)//'degrees',ANAL)
     call print('   with distance -1/2 b -- '//O//' = '//round(r,5)//'A',ANAL)

     if (gaussian_smoothing) then !smear the position along axis
        !call system_abort('not implemented.')
        do sample_i=1, n_pos_bins
          sample_r = (real(sample_i,dp)-0.5_dp)*pos_bin_width
          dist = abs(r - sample_r)
          !Include all the atoms, slow but minimises error
          !	  if (dist > 4.0_dp*gaussian_sigma) cycle
            exp_arg = -0.5_dp*(dist/(pos_gaussian_sigma))**2
            if (exp_arg > -20.0_dp) then ! good to about 1e-8
              histogram(int(orientation_angle/angle_bin_width)+1,sample_i) = histogram(int(orientation_angle/angle_bin_width)+1,sample_i) + exp(exp_arg)/(pos_gaussian_sigma*sqrt(2.0_dp*PI)) !Gaussian in 1 dimension
            endif
        end do ! sample_i

     else !no gaussian_smoothing
        histogram(int(orientation_angle/angle_bin_width)+1,int(r/pos_bin_width)+1) = histogram(int(orientation_angle/angle_bin_width)+1,int(r/pos_bin_width)+1) + 1._dp
     endif

  end do ! O

  !normalise for the number of molecules in each pos_bin
  do sample_i=1,n_pos_bins
     sum_counts = sum(histogram(1:n_angle_bins,sample_i))
     if (sum_counts /= 0) histogram(1:n_angle_bins,sample_i) = histogram(1:n_angle_bins,sample_i) / sum_counts
  enddo

  !normalise for different solid angles of each angle_bin
  do sample_i=1, n_angle_bins
     histogram(sample_i,1:n_pos_bins) = histogram(sample_i,1:n_pos_bins) / angle_bin_w(sample_i)
  enddo 

end subroutine water_orientation_calc

end module structure_analysis_module

program structure_analysis
use libatoms_module
use structure_analysis_module
implicit none

  type(Dictionary) :: cli_params

  character(len=FIELD_LENGTH) :: infilename
  integer :: decimation
  type(Inoutput) :: list_infile
  type (CInoutput) :: infile
  logical :: infile_is_list
  logical :: quiet

  character(len=FIELD_LENGTH) :: commandfilename
  type(Inoutput) :: commandfile

  character(len=10240) :: args_str, myline
  integer :: n_analysis_a
  type(analysis), allocatable :: analysis_a(:)

  logical :: more_files
  integer :: status, arg_line_no
  real(dp) :: time

  integer :: i_a, frame_count, raw_frame_count
  type(Atoms) :: structure
  logical :: do_verbose

  call system_initialise(NORMAL)

  call initialise(cli_params)
  call param_register(cli_params, "verbose", "F", do_verbose)
  if (.not. param_read_args(cli_params, ignore_unknown=.true.)) &
    call system_abort("Impossible failure to parse verbosity")
  call finalise(cli_params)
  if (do_verbose) then
    call system_initialise(verbosity=VERBOSE)
  endif

  call initialise(cli_params)
  commandfilename=''
  call param_register(cli_params, "commandfile", '', commandfilename)
  call param_register(cli_params, "infile", "stdin", infilename)
  call param_register(cli_params, "decimation", "1", decimation)
  call param_register(cli_params, "infile_is_list", "F", infile_is_list)
  call param_register(cli_params, "quiet", "F", quiet)
  if (.not. param_read_args(cli_params, ignore_unknown = .true., task="CLI")) then
    call system_abort("Failed to parse CLI")
  endif
  if (len_trim(commandfilename) == 0) then
    allocate(analysis_a(1))
    call analysis_read(analysis_a(1))
  else
    if (.not. param_read_args(cli_params, ignore_unknown = .false., task="CLI_again")) then
      call system_abort("Failed to parse CLI again after getting a commandfile, most likely passed in some analysis specific flags on command line")
    endif
    call initialise(commandfile, trim(commandfilename), INPUT)
    arg_line_no = 1
    myline = read_line(commandfile)
    read (unit=myline,fmt=*) n_analysis_a
    allocate(analysis_a(n_analysis_a))
    do i_a=1, n_analysis_a
      args_str = read_line(commandfile)
      if (i_a == 1) then
        call analysis_read(analysis_a(i_a), args_str=args_str)
      else
        call analysis_read(analysis_a(i_a), analysis_a(i_a-1), args_str)
      endif
    end do
  endif
  call finalise(cli_params)

  call check_analyses(analysis_a)

  more_files = .true.
  if (infile_is_list) then
    call initialise(list_infile, trim(infilename), INPUT)
    infilename = read_line(list_infile, status)
    more_files = .false.
    if (status == 0) more_files = .true.
  endif

  raw_frame_count = decimation-1
  frame_count = 0
  do while (more_files)

    call print(trim(infilename))
    call initialise(infile, infilename, INPUT)
    call read(structure, infile, status=status, frame=raw_frame_count)
    do while (status == 0)
      frame_count = frame_count + 1
      if (.not. quiet) then
        if (mod(frame_count,1000) == 1) write (mainlog%unit,'(I7,a,$)') frame_count," "
        if (mod(frame_count,10) == 0) write (mainlog%unit,'(I1,$)') mod(frame_count/10,10)
        if (mod(frame_count,1000) == 0) write (mainlog%unit,'(a)') " "
      endif

      if (.not. get_value(structure%params,"Time",time)) then
        time = -1.0_dp
      endif
      call do_analyses(analysis_a, time, frame_count, structure)
      call finalise(structure)

      raw_frame_count = raw_frame_count + decimation
      ! get ready for next structure
      call read(structure, infile, status=status, frame=raw_frame_count)
    end do
    raw_frame_count = raw_frame_count - decimation

    ! get ready for next file
    more_files = .false.
    call finalise(infile)
    if (infile_is_list) then
      infilename = read_line(list_infile, status)
      if (status == 0) then
        more_files = .true.
      endif
      if (infile%n_frame > 0) then
	raw_frame_count = (decimation-1)-(infile%n_frame-1-raw_frame_count)
      else
	raw_frame_count = decimation-1
      endif
    endif
    write (mainlog%unit,'(a)') " "
    frame_count = 0
  end do ! more_files
  if (infile_is_list) call finalise(list_infile)

  call print_analyses(analysis_a)

end program structure_analysis
