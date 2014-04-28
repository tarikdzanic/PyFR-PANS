# -*- coding: utf-8 -*-

from abc import ABCMeta, abstractmethod, abstractproperty
import re

from mpmath import mp
import numpy as np

from pyfr.nputil import chop
from pyfr.polys import get_polybasis
from pyfr.quadrules import get_quadrule
from pyfr.nputil import block_diag
from pyfr.util import lazyprop


class BaseBasis(object):
    __metaclass__ = ABCMeta

    name = None
    ndims = -1

    nspts_coeffs = None
    nspts_cdenom = None

    def __init__(self, nspts, cfg):
        self.nspts = nspts
        self.cfg = cfg
        self.order = cfg.getint('solver', 'order')

        self.antialias = cfg.get('solver', 'anti-alias', 'none')
        self.antialias = set(s.strip() for s in self.antialias.split(','))
        self.antialias.discard('none')
        if self.antialias - {'flux', 'div-flux'}:
            raise ValueError('Invalid anti-alias options')

        self.ubasis = get_polybasis(self.name, self.order + 1, self.upts)

        if nspts:
            self.nsptsord = nsptord = self.order_from_nspts(nspts)
            self.sbasis = get_polybasis(self.name, nsptord, self.spts)

    @abstractmethod
    def std_ele(sptord):
        pass

    @classmethod
    def nspts_from_order(cls, sptord):
        return int(mp.polyval(cls.nspts_coeffs, sptord)) // cls.nspts_cdenom

    @classmethod
    def order_from_nspts(cls, nspts):
        # Obtain the coefficients for the poly: P(n) - nspts = 0
        coeffs = list(cls.nspts_coeffs)
        coeffs[-1] -= cls.nspts_cdenom*nspts

        # Solve to obtain the order (a positive integer)
        roots = mp.polyroots(coeffs)
        roots = [int(x) for x in roots if mp.isint(x) and x > 0]

        if roots:
            return roots[0]
        else:
            raise ValueError('Invalid number of shape points')

    @chop
    def opmat(self, expr):
        if not re.match(r'[M0-9\-+*() ]+$', expr):
            raise ValueError('Invalid operator matrix expression')

        mats = {m: np.asmatrix(getattr(self, m.lower()))
                for m in re.findall(r'M\d+', expr)}

        return np.asarray(eval(expr, {'__builtins__': None}, mats))

    @lazyprop
    def m0(self):
        return self.ubasis.nodal_basis_at(self.fpts)

    @lazyprop
    def m1(self):
        m = np.rollaxis(self.ubasis.jac_nodal_basis_at(self.upts), 2)
        return m.reshape(self.nupts, -1)

    @lazyprop
    def m2(self):
        m = self.norm_fpts[...,None]*self.m0[:,None,:]
        return m.reshape(self.nfpts, -1)

    @lazyprop
    def m3(self):
        return self.fbasis_at(self.upts)

    @lazyprop
    def m4(self):
        m = self.m1.reshape(self.nupts, -1, self.nupts).swapaxes(0, 1)
        return m.reshape(-1, self.nupts)

    @lazyprop
    def m6(self):
        m = self.norm_fpts.T[:,None,:]*self.m3
        return m.reshape(-1, self.nfpts)

    @lazyprop
    def m7(self):
        return self.ubasis.nodal_basis_at(self.qpts)

    @lazyprop
    def m8(self):
        return np.vstack([self.m0, self.m7])

    @lazyprop
    @chop
    def m9(self):
        ub = self.ubasis
        return np.dot(ub.vdm.T, self.qwts*ub.ortho_basis_at(self.qpts))

    @property
    def m10(self):
        return block_diag([self.m9]*self.ndims)

    @abstractproperty
    def nupts(self):
        pass

    @lazyprop
    def upts(self):
        rname = self.cfg.get('solver-elements-' + self.name, 'soln-pts')
        return get_quadrule(self.name, rname, self.nupts).points

    @lazyprop
    def _qrule(self):
        sect = 'solver-elements-' + self.name
        kwargs = {'flags': 'sp'}

        if self.cfg.hasopt(sect, 'quad-pts'):
            kwargs['rule'] = self.cfg.get(sect, 'quad-pts')

        if self.cfg.hasopt(sect, 'quad-deg'):
            kwargs['qdeg'] = self.cfg.getint(sect, 'quad-deg')

        return get_quadrule(self.name, **kwargs)

    @property
    def qpts(self):
        return self._qrule.np_points

    @property
    def nqpts(self):
        return len(self.qpts)

    @property
    def qwts(self):
        return self._qrule.np_weights

    @abstractproperty
    def fpts(self):
        pass

    @abstractproperty
    def fbasis_coeffs(self):
        pass

    def _fbasis_coeffs_for(self, ftype, fproj, fdjacs, nffpts):
        # Suitable quadrature rules for various face types
        qrule_map = {
            'line': ('gauss-legendre', self.order + 1),
            'quad': ('gauss-legendre', (self.order + 1)**2),
            'tri': ('williams-shunn', 36)
        }

        # Obtain a quadrature rule for integrating on the face
        qrule = get_quadrule(ftype, *qrule_map[ftype])

        # Project the rule points onto the various faces
        proj = fproj(*np.atleast_2d(qrule.np_points.T))
        qfacepts = np.vstack(list(np.broadcast(*p)) for p in proj)

        # Obtain a nodal basis on the reference face
        fname = self.cfg.get('solver-interfaces-' + ftype, 'flux-pts')
        ffpts = get_quadrule(ftype, fname, nffpts)
        nodeb = get_polybasis(ftype, self.order + 1, ffpts.np_points)

        L = nodeb.nodal_basis_at(qrule.np_points)

        M = self.ubasis.ortho_basis_at(qfacepts)
        M = M.reshape(-1, len(proj), len(qrule.np_points))

        # Do the quadrature
        S = np.einsum('i...,ik,jli->lkj', qrule.np_weights, L, M)

        # Account for differing face areas
        S *= np.asanyarray(fdjacs)[:,None,None]

        return S.reshape(-1, self.nupts)

    @chop
    def fbasis_at(self, pts):
        return np.dot(self.fbasis_coeffs, self.ubasis.ortho_basis_at(pts)).T

    @abstractproperty
    def facenorms(self):
        pass

    @lazyprop
    def norm_fpts(self):
        fnorms = self.facenorms
        return np.vstack([fn]*n for fn, n in zip(fnorms, self.nfacefpts))

    @lazyprop
    def spts(self):
        return self.std_ele(self.nsptsord - 1)

    @abstractproperty
    def facefpts(self):
        pass

    @lazyprop
    def nfacefpts(self):
        return [len(f) for f in self.facefpts]

    @property
    def nfpts(self):
        return sum(self.nfacefpts)
