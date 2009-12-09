"""This module provides a high-level interface between quippy and the AtomEye extension module
   :mod:`quippy._atomeye`. """

import _atomeye, sys, numpy, time, os
from math import ceil, log10
from farray import *

ATOMEYE_MAX_AUX_PROPS = 48

default_settings = {'n->xtal_mode': 1,
                    'n->suppress_printout': 1,
                    'n->bond_mode': 1,
                    'n->atom_r_ratio': 0.5,
                    'key->BackSpace': 'load_config_backward'
                    }

def on_click(iw, idx):
    if not iw in views:
        raise RuntimeError('Unexpected window id %d' % iw)
    views[iw].on_click(idx)
    

def on_advance(iw, mode):
    if not iw in views:
        raise RuntimeError('Unexpected window id %d' % iw)
    views[iw].on_advance(mode)

def on_close(iw):
    if not iw in views:
        raise RuntimeError('Unexpected window id %d' % iw)
    views[iw].on_close()


def on_new_window(iw):
    if iw in views:
        views[iw].is_alive = True
    else:
        views[iw] = AtomEyeView(window_id=iw)
    

class AtomEyeView(object):
    def __init__(self, atoms=None, window_id=None, copy=None, frame=1, delta=1, property=None, arrows=None, nowindow=0,
                 *arrowargs, **arrowkwargs):
        self.atoms = atoms
        self.frame = frame
        self.delta = delta

        self.paint_property = None
        self.paint_value = 1

        self.is_alive = False

        if window_id is None:
            self.start(copy, nowindow)
        else:
            self._window_id = window_id
            self.is_alive = True
            views[self._window_id] = self

        global view
        if view is None:
            view = self

        if property is not None or arrows is not None:
            self.redraw(property=property, arrows=arrows, *arrowargs, **arrowkwargs)
            
    def start(self, copy=None, nowindow=0):
        if self.is_alive: return
        
        if self.atoms is None:
            theat = None
            title = 'null'
        else:
            if hasattr(self.atoms, '__iter__'):
                theat = self.atoms[self.frame]
                fmt = "%%0%dd" % ceil(log10(len(self.atoms)+1))
                title = 'AtomsList[%s] len=%s' % (fmt % self.frame, fmt % len(self.atoms))

            else:
                theat = self.atoms
                title = 'Atoms'

        icopy = -1
        if copy is not None:
            if isinstance(copy, AtomEye):
                icopy = copy._window_id
            elif isinstance(copy, int):
                icopy = copy
            else:
                raise TypeError('copy should be either an int or an AtomEye instance')

        self.is_alive = False
        self._window_id = _atomeye.open_window(icopy,theat,nowindow)
        views[self._window_id] = self
        while not self.is_alive:
            time.sleep(0.1)
        time.sleep(0.3)
        _atomeye.set_title(self._window_id, title)
        self.update(default_settings)

    def on_click(self, idx):
        if self.atoms is None: return
        theat = self.atoms
        if hasattr(self.atoms, '__iter__'):
            theat = self.atoms[self.frame]

        if idx >= theat.n:
            idx = idx % theat.n
        idx = idx + 1 # atomeye uses zero based indices            
        print "frame %d, atom %d clicked" % (self.frame, idx)
        d = theat[idx]
        for k in sorted(d):
            v = d[k]
            if isinstance(v, FortranArray) and v.dtype.kind == 'f' and len(v) > 1:
                print '%s = %s (norm %f)' % (k, v, v.norm())
            else:
                print '%s = %s' % (k, v)
        print
        sys.stdout.flush()

        if self.paint_property is not None and theat.has_property(self.paint_property):
            getattr(theat, self.paint_property)[idx] = self.paint_value
            self.redraw()


    def on_advance(self, mode):
        if not hasattr(self.atoms,'__iter__'): return

        if mode == 'forward':
            self.frame += self.delta
        elif mode == 'backward':
            self.frame -= self.delta
        elif mode == 'first':
            self.frame = 1
        elif mode == 'last':
            self.frame = len(self.atoms)

        if self.frame > len(self.atoms):
            try:
                self.atoms[self.frame]
            except IndexError:
                self.frame = ((self.frame-1) % len(self.atoms)) + 1
                
        if self.frame < 1:
            self.frame = ((self.frame-1) % len(self.atoms)) + 1
        self.redraw()


    def on_close(self):
        global view
        
        self.is_alive = False
        if view is self:
            view = None
        del views[self._window_id]


    def paint(self, property='selection',value=1,fill=0):
        if self.atoms is None: return
        if not self.atoms.has_property(property):
            self.atoms.add_property(property, fill)
        self.paint_property = property
        self.paint_value = value
        _atomeye.load_atoms(self._window_id, 'paint', self.atoms)
        self.aux_property_coloring(self.paint_property)


    def show(self, obj, property=None, frame=None, arrows=None, *arrowargs, **arrowkwargs):
        self.atoms = obj
        if hasattr(obj,'__iter__'):
            if frame is not None:
                if frame < 0: frame = len(self.atoms)-frame
                if frame >= len(self.atoms):
                    try:
                        self.atoms[self.frame]
                    except IndexError:
                        frame=len(self.atoms)-1
                self.frame = frame
                
        self.redraw(property=property, arrows=arrows, *arrowargs, **arrowkwargs)

    
    def redraw(self, property=None, arrows=None, *arrowargs, **arrowkwargs):
        if not self.is_alive:
            raise RuntimeError('is_alive is False')

        if self.atoms is None:
            raise RuntimeError('Nothing to view -- set self.atoms to Atoms or sequence of Atoms')

        theat = self.atoms
        if hasattr(self.atoms, '__iter__'):
            theat = self.atoms[self.frame]
            fmt = "%%0%dd" % ceil(log10(len(self.atoms)+1))
            title = 'AtomsList[%s] len=%s' % (fmt % self.frame, fmt % len(self.atoms))
        else:
            title = 'Atoms'

        if property is not None:
            if isinstance(property,str):
                pass
            elif isinstance(property,int):
                theat.add_property('_show', False)
                theat._show[:] = [i == property for i in frange(theat.n)]
                property = '_show'
            else:
                if isinstance(property, numpy.ndarray):
                    if theat.has_property('_show'):
                        theat.remove_property('_show')
                    theat.add_property('_show', property.flat[0],
                                       len(property.shape) == 1 and 1 or property.shape[0])
                else:
                    theat.add_property('_show', property)
                theat._show[...] = property
                property = '_show'

            # Make sure property we're looking at is in the first 48 columns, or it won't be available
            if sum((theat.data.intsize, theat.data.realsize, theat.data.logicalsize, theat.data.strsize)) > ATOMEYE_MAX_AUX_PROPS:

                col = 0
                for p in theat.properties:
                    col += theat.properties[p][3] - theat.properties[p][2] + 1
                    if p == property:
                        break

                if col >= ATOMEYE_MAX_AUX_PROPS:
                    theat.properties.swap(theat.properties.keys()[2], property)

	_atomeye.load_atoms(self._window_id, title, theat)
        if property is not None:
            self.aux_property_coloring(property)

        if arrows is not None:
            self.draw_arrows(arrows, *arrowargs, **arrowkwargs)

    def run_command(self, command):
        if not self.is_alive: 
            raise RuntimeError('is_alive is False')
        _atomeye.run_command(self._window_id, command)

    def __call__(self, command):
        self.run_command(command)

    def close(self):
        self.run_command('close')

    def update(self, D):
        for k, v in D.iteritems():
            self.run_command("set %s %s" % (str(k), str(v)))

    def save(self, filename):
        self.run_command("save %s" % str(filename))

    def load_script(self, filename):
        self.run_command("load_script %s" % str(filename))

    def key(self, key):
        self.run_command("key %s" % key)

    def toggle_coordination_coloring(self):
        self.run_command("toggle_coordination_coloring")

    def translate(self, axis, delta):
        self.run_command("translate %d %f " % (axis, delta))

    def shift_xtal(self, axis, delta):
        self.run_command("shift_xtal %d %f" % (axis, delta))

    def rotate(self, axis, theta):
        self.run_command("rotate %d %f" % (axis, theta))

    def advance(self, delta):
        self.run_command("advance %f" % delta)

    def shift_cutting_plane(self, delta):
        self.run_command("shift_cutting_plane %f" % delta)

    def change_bgcolor(self, color):
        self.run_command("change_bgcolor %f %f %f" % (color[0], color[1], color[2]))

    def change_atom_r_ratio(self, delta):
        self.run_command("change_atom_r_ratio %f" % delta)

    def change_bond_radius(self, delta):
        self.run_command("change_bond_radius %f" % delta)

    def change_view_angle_amplification(self, delta):
        self.run_command("change_view_angle_amplification %f" % delta)

    def toggle_parallel_projection(self):
        self.run_command("toggle_parallel_projection")

    def toggle_bond_mode(self):
        self.run_command("toggle_bond_mode" )

    def normal_coloring(self):
        self.run_command("normal_coloring")

    def aux_property_coloring(self, auxprop):
        self.run_command("aux_property_coloring %s" % str(auxprop))

    def central_symmetry_coloring(self):
        self.run_command("central_symmetry_coloring")

    def change_aux_property_threshold(self, lower_upper, delta):
        if isinstance(lower_upper, int): lower_upper = str(lower_upper)
        self.run_command("change_aux_property_threshold %s %f" % (lower_upper, delta))

    def reset_aux_property_thresholds(self):
        self.run_command("reset_aux_property_thresholds")

    def toggle_aux_property_thresholds_saturation(self):
        self.run_command("toggle_aux_property_thresholds_saturation")

    def toggle_aux_property_thresholds_rigid(self):
        self.run_command("toggle_aux_property_thresholds_rigid")

    def rcut_patch(self, sym1, sym2, inc_dec, delta=None):
        self.run_command("rcut_patch start %s %s" % (sym1,sym2))
        if delta is None:
            self.run_command("rcut_patch %s" % inc_dec)
        else:
            self.run_command("rcut_patch %s %f" % (inc_dec, delta))
        self.run_command("rcut_patch finish")

    def select_gear(self, gear):
        self.run_command("select_gear %d" % gear)

    def cutting_plane(self, n, d, s):
        self.run_command("cutting_plane %d %f %f %f %f %f %f" % \
                                 (n, d[0], d[1], d[2], s[0], s[1], s[2]))

    def shift_cutting_plane_to_anchor(self, n):
        self.run_command("shift_cutting_plane_to_anchor %d" % n)

    def delete_cutting_plane(self, n):
        self.run_command("delete_cutting_plane %d" % n)

    def flip_cutting_plane(self, n):
        self.run_command("flip_cutting_plane %d" % n)

    def capture(self, filename, resolution=None):
        if resolution is None: resolution = ""
        format = filename[filename.rindex('.')+1:]
        self.run_command("capture %s %s %s" % (format, filename, resolution))

    def change_wireframe_mode(self, ):
        self.run_command("change_wireframe_mode")

    def change_cutting_plane_wireframe_mode(self):
        self.run_command("change_cutting_plane_wireframe_mode")

    def load_config(self, filename):
        self.run_command("load_config %s" % filename)

    def load_config_advance(self, command):
        self.run_command("load_config_advance %s" % command)

    def script_animate(self, filename):
        self.run_command("script_animate %s" % filename)

    def load_atom_color(self, filename):
        self.run_command("load_atom_color %s" % filename)

    def load_aux(self, filename):
        self.run_command("load_aux %s" % filename)

    def look_at_the_anchor(self):
        self.run_command("look_at_the_anchor")

    def observer_goto(self):
        self.run_command("observer_goto")

    def xtal_origin_goto(self, s):
        self.run_command("xtal_origin_goto %f %f %f" % (s[0], s[1], s[2]))

    def find_atom(self, i):
        self.run_command("find_atom %d" % (i-1))

    def resize(self, width, height):
        self.run_command("resize %d %d" % (width, height))

    def change_aux_colormap(self, n):
        self.run_command("change_aux_colormap %d" % n)

    def print_atom_info(self, i):
        self.run_command("print_atom_info %d" % i)

    def save_atom_indices(self):
        self.run_command("save_atom_indices")

    def change_central_symm_neighbormax(self):
        self.run_command("change_central_symm_neighbormax")

    def timer(self, label):
        self.run_command("timer %s" % label)

    def isoatomic_reference_imprint(self):
        self.run_command("isoatomic_reference_imprint")

    def toggle_shell_viewer_mode(self):
        self.run_command("toggle_shell_viewer_mode")

    def toggle_xtal_mode(self):
        self.run_command("toggle_xtal_mode")

    def change_shear_strain_subtract_mean(self):
        self.run_command("change_shear_strain_subtract_mean")

    def draw_arrows(self, property, scale_factor=0.0, head_height=0.1, head_width=0.05, up=(0.0,1.0,0.0)):
        if property == 'off':
            self.run_command('draw_arrows off')
        else:
            self.run_command('draw_arrows %s %f %f %f %f %f %f' %
                             (str(property), scale_factor, head_height, head_width, up[0], up[1], up[2]))

    def wait(self):
        """Sleep until this AtomEye viewer has finished processing all queued events."""
        if not self.is_alive: 
            raise RuntimeError('is_alive is False')
        _atomeye.wait(self._window_id)


    def make_movie(self, atomsseq, moviefilename, progress=True,
                   movieencoder='ffmpeg -i %s -r 25 -b 30M %s', movieplayer='mplayer %s', cleanup=True,
                   postprocess=None, nframes=None):
        """Make a movie using configurations from `atomsseq`. A sequence of JPEG files are
        written and then encoded using `movieencoder` to form an MPEG - the default
        command is ``fmpeg -i %s -r 25 -b 30M %s``. Optional arguments `start`, `stop` and `step`
        can be used to limit the frames used for the movie. A textual progress bar will be
        drawn unless `progress` is set to false. The intermediate JPEG files are cleared up
        after the movie is made."""

        from quippy.progbar import ProgressBar

        ndigit = 5
        if nframes is not None: ndigit = int(ceil(log10(nframes)))
        
        basename, ext = os.path.splitext(moviefilename)
        fmt = '%s%%0%dd.jpg' % (basename, ndigit)
        progress = progress and nframes is not None

        imgs = []
        if progress: pb = ProgressBar(0,nframes,80,showValue=True)
        try:
            if progress: print 'Rendering frames...'
            for i, at in enumerate(atomsseq):
                filename = fmt % i
                
                self.show(at)
                self.capture(filename)
                self.wait()
                if postprocess is not None:
                    postprocess(at, i, filename)
                imgs.append(filename)
                if progress: pb(i+1)
            if progress: print

            if movieencoder is not None:
                if progress: print 'Encoding movie'
                os.system(movieencoder % (fmt, moviefilename))

            if movieplayer is not None:
                if progress: print 'Playing movie'
                os.system(movieplayer % moviefilename)
           
        finally:
            if cleanup:
                self.wait()
                for img in imgs:
                    if os.path.exists(img): os.remove(img)


views = {}
_atomeye.set_handlers(on_click, on_close, on_advance, on_new_window)


view = None

def show(obj, property=None, frame=1, window_id=None, nowindow=False, arrows=None, *arrowargs, **arrowkwargs):
    """Convenience function to show obj in the default AtomEye view

    If window_id is not None, then this window will be used. Otherwise
    the default window is used, initialising it if necessary.
    
    Returns instance of AtomEyeView."""
    global view

    # if window_id was passed in, then use that window
    if window_id is not None:
        views[window_id].show(obj, property, frame)
        return views[window_id]

    # otherwise use the default viewer, initialising it if necessary
    if view is None:
        if views.keys():
            view = views[views.keys()[0]]
            view.show(obj, property, frame)
        else:
            view = AtomEyeView(obj, property=property, frame=frame, nowindow=nowindow, arrows=arrows, *arrowargs, **arrowkwargs)
    else:
        view.show(obj, property, frame, arrows=arrows, *arrowargs, **arrowkwargs)

    return view


class AtomEyeCfgWriter(object):
    """Write atoms in AtomEye extended CFG format. Returns a list of auxiliary properties
    actually written to CFG file, which may be abbreviated compared to those requested since
    AtomEye has a maximum of 32 aux props."""

    def __init__(self, cfg=sys.stdout, shift=farray([0.,0.,0.]), properties=None):

        if type(cfg) == type(''):
            self.cfg = open(cfg, 'w')
            self.opened = True
        else:
            self.cfg = cfg
            self.opened = False

        self.shift = shift
        self.properties = properties

    def close(self):
        if self.opened: self.cfg.close()

    def write(self, at):
        
        if self.properties is None:
            self.properties = at.properties.keys()

        # Header line
        at.cfg.write('Number of particles = %d\n' % at.n)
        cfg.write('# '+at.comment(properties)+'\n')

        # Lattice vectors
        for i in 1,2,3:
            for j in 1,2,3:
                cfg.write('H0(%d,%d) = %16.8f\n' % (i, j, at.lattice[j,i]))

        cfg.write('.NO_VELOCITY.\n')

        # Check first property is position-like
        species = getattr(self,properties[0])
        if len(species.shape) != 1 or species.dtype.kind != 'S':
            raise ValueError('First property must be species like')

        pos = getattr(self,properties[1])
        if pos.shape[1] != 3 or pos.dtype.kind != 'f':
            raise ValueError('Second property must be position like')

        if not at.properties.has_key('frac_pos'):
            at.add_property('frac_pos',0.0,ncols=3)
            at.frac_pos[:] = farray([ numpy.dot(pos[i,:],at.g) + shift for i in range(at.n) ])

        if not at.properties.has_key('mass'):
            at.add_property('mass', map(ElementMass.get, at.species))

        properties = filter(lambda p: p not in ('pos','frac_pos','mass','species'), properties)

        # AtomEye can handle a maximum of 32 columns, so we might have to throw away
        # some of the less interesting propeeties

        def count_cols():
            n_aux = 0
            for p in properties:
                s = getattr(self,p).shape
                if len(s) == 1: n_aux += 1
                else:           n_aux += s[1]
            return n_aux

        boring_properties = ['travel','avgpos','oldpos','acc','velo']
        while count_cols() > 32:
            if len(boring_properties) == 0:
                raise ValueError('No boring properties left!')
            try:
                next_most_boring = boring_properties.pop(0)
                del properties[properties.index(next_most_boring)]
            except IndexError:
                pass # this boring property isn't in the list: move on to next

        properties = ['species','mass','frac_pos'] + properties
        data = at.to_recarray(properties)

        cfg.write('entry_count = %d\n' % (len(data.dtype.names)-2))

        # 3 lines per atom: element name, mass and other data
        format = '%s\n%12.4f\n'
        for i,name in enumerate(data.dtype.names[2:]):
            if i > 2: cfg.write('auxiliary[%d] = %s\n' % (i-3,name))
            format = format + _getfmt(data.dtype.fields[name][0])
        format = format + '\n'

        for i in range(at.n):
            cfg.write(format % tuple(data[i]))


