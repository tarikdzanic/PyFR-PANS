# -*- coding: utf-8 -*-
<%namespace module='pyfr.backends.base.makoutil' name='pyfr'/>
<%include file='pyfr.solvers.euler.kernels.flux1d'/>
<%include file='pyfr.solvers.euler.kernels.flux'/>

<% t_tol = 0.99 %>
<% gmrtg = (c['gamma']-1.0)/(2.0*c['gamma']) %>
<% gprtg = (c['gamma']+1.0)/(2.0*c['gamma']) %>
<% tgrgm = (2.0*c['gamma'])/(c['gamma']-1.0) %>
<% tgrgp = (2.0*c['gamma'])/(c['gamma']+1.0) %>
<% trgm = 2.0/(c['gamma']-1.0) %>
<% trgp = 2.0/(c['gamma']+1.0) %>
<% gmrgp = (c['gamma']-1.0)/(c['gamma']+1.0) %>
<% hgm = 0.5*(c['gamma']-1.0) %>
<% rgm = 1./(c['gamma']-1.0) %>
<% gamma = c['gamma'] %>

// Initial guess for pressure
<%pyfr:macro name='init_p' params='rl,vl,pl,cl,rr,vr,pr,cr,p0'>
    fpdtype_t bpv = 0.5*(pl + pr) + 0.125*(vl[0] - vr[0])*(rl + rr)*(cl + cr);
    bpv = max(0.,bpv);
    fpdtype_t pmin = min(pl,pr);
    fpdtype_t pmax = max(pl,pr);
    fpdtype_t rpmax = pmax/pmin;

    if ((rpmax <= 2.) && (pmin <= bpv) && (bpv <= pmax)){
        p0 = bpv;
    }
    else if (bpv < pmin){
        // Two-rarefaction Riemann solve
        fpdtype_t pre = pow(pl/pr,${gmrtg});
        fpdtype_t um  = (pre*vl[0]/cl + vr[0]/cr + ${trgm}*(pre - 1.0))/(pre/cl + 1./cr);

        fpdtype_t ptl = 1. - ${hgm}*(um - vl[0])/cl;
        fpdtype_t ptr = 1. + ${hgm}*(um - vr[0])/cr;

        p0 = 0.5*(pl*pow(ptl,${tgrgm}) + pr*pow(ptr,${tgrgm}));
    }
    else{
        // Two-shock Riemann solve
        fpdtype_t gl = sqrt((${trgp}/rl)/(${gmrgp}*pl + bpv));
        fpdtype_t gr = sqrt((${trgp}/rr)/(${gmrgp}*pr + bpv));
        p0 = (gl*pl + gr*pr - (vr[0] - vl[0]))/(gl + gr);
    }
</%pyfr:macro>

// Star Flux, assuming covolume = 0. See Toro 2009 Eq.(4.86-4.87)
<%pyfr:macro name='star_flux' params='p, ps, rs, cs, f, fd'>
    if (p <= ps){
       fpdtype_t pr = p/ps;
       f  = ${trgm}*cs*(pow(pr,${gmrtg}) - 1.);
       fd = pow(pr,${-gprtg})/(rs*cs);
    }
    else{
       fpdtype_t as = ${trgp}/rs;
       fpdtype_t bs = ${gmrgp}*ps;
       fpdtype_t sapb = sqrt(as/(p + bs));
       f  = (p - ps)*sapb;
       fd = (1. - 0.5*(p - ps)/(p + bs))*sapb;
    }
</%pyfr:macro>

// Primitive to inviscid flux
// w = [density, v_1,..., v_ndims, p]^T
<%pyfr:macro name='primitive_1dflux' params='w, f'>
    fpdtype_t invrho = 1.0/w[0];

    // Compute the velocities
    fpdtype_t rhov[${ndims}];
% for i in range(ndims):
    rhov[${i}] = w[0]*w[${i + 1}];
% endfor

    // Compute the Energy
    fpdtype_t E = w[${nvars-1}]*${rgm} + 0.5*invrho*(${pyfr.dot('rhov[{i}]', i=ndims)});

    // Density and energy fluxes
    f[0] = rhov[0];
    f[${nvars - 1}] = (E + w[${nvars-1}])*w[1];

    // Momentum fluxes
% for i in range(ndims):
% if i == 0:
    f[${i+1}]= rhov[0]*w[${i+1}] + w[${nvars-1}];
% else:
    f[${i+1}]= rhov[0]*w[${i+1}];
% endif
% endfor
</%pyfr:macro>


// Exact solve solution decision tree
<% switch = 0.0 %>
<%pyfr:macro name='riemann_decision' params='rl,vl,pl,cl,rr,vr,pr,cr,us,p0,w0'>

    if (${switch} <= us){
% for i in range(ndims-1):
        w0[${i+2}] = vl[${i+1}];
% endfor
        if (p0 <= pl){
            if (${switch} <= (vl[0] - cl)){
                w0[0] = rl;
                w0[1] = vl[0];
                w0[${nvars-1}] = pl;
            }
            else {
                fpdtype_t cml = cl*pow(p0/pl,${gmrtg});
                if (${switch} > (us - cml)){
                    w0[0] = rl*pow(p0/pl, ${1./gamma});
                    w0[1] = us;
                    w0[${nvars-1}] = p0;
                }
                else {
                    fpdtype_t c = ${trgp}*(cl + ${hgm}*(vl[0] - ${switch}));
                    w0[0] = rl*pow(c/cl,${trgm});
                    w0[1] = ${trgp}*(cl + ${hgm}*vl[0] + ${switch});
                    w0[${nvars-1}] = pl*pow(c/cl,${tgrgm});
                }
            }
        }
        else{
            fpdtype_t p0p = p0/pl;
            fpdtype_t sl = vl[0] - cl*sqrt(${gprtg}*p0p + ${gmrtg});
            if (${switch} <= sl){
                w0[0] = rl;
                w0[1] = vl[0];
                w0[${nvars-1}] = pl;
            }
            else {
                w0[0] = rl*(p0p + ${gmrgp})/(p0p*${gmrgp} + 1.);
                w0[1] = us;
                w0[${nvars-1}] = p0;
            }
        }
    }
    else{
% for i in range(ndims-1):
        w0[${i+2}] = vr[${i+1}];
% endfor
        if (p0 > pr){
            fpdtype_t p0p = p0/pr;
            fpdtype_t sr = vr[0] + cr*sqrt(${gprtg}*p0p + ${gmrtg});
            if (${switch} >= sr){
                w0[0] = rr;
                w0[1] = vr[0];
                w0[${nvars-1}] = pr;
            }
            else {
                w0[0] = rr*(p0p + ${gmrgp})/(p0p*${gmrgp} + 1.);
                w0[1] = us;
                w0[${nvars-1}] = p0;
            }
        }
        else {
            if (${switch} >= (vr[0] + cr)){
                w0[0] = rr;
                w0[1] = vr[0];
                w0[${nvars-1}] = pr;
            }
            else {
                fpdtype_t p0p = p0/pr;
                fpdtype_t cmr = cr*pow(p0p,${gmrtg});
                if (${switch} <= (us + cmr)){
                    w0[0] = rr*pow(p0p, ${1./gamma});
                    w0[1] = us;
                    w0[${nvars-1}] = p0;
                }
                else{
                    fpdtype_t c = ${trgp}*(cr - ${hgm}*(vr[0] - ${switch}));
                    w0[0] = rr*pow(c/cr,${trgm});
                    w0[1] = ${trgp}*(-cr + ${hgm}*vr[0] + ${switch});
                    w0[${nvars-1}] = pr*pow(c/cr,${tgrgm});
                }
            }
        }
    }

</%pyfr:macro>

// Godunov exact Riemann solver
<% kmax = 3 %>
<% pmin = 0.00001 %>
<%pyfr:macro name='rsolve_t1d' params='ul, ur, nf'>
    // Compute the left and right fluxes + velocities and pressures
    fpdtype_t fl[${nvars}],fr[${nvars}];
    fpdtype_t vl[${ndims}],vr[${ndims}];
    fpdtype_t pl,pr,p0,p1;
    fpdtype_t fsl,fsr,fdl,fdr;
    fpdtype_t w0[${nvars}];

    ${pyfr.expand('inviscid_1dflux','ul','fl','pl','vl')};
    ${pyfr.expand('inviscid_1dflux','ur','fr','pr','vr')};

    // Calculate Left/Right sound speeds
    fpdtype_t cl = sqrt(${c['gamma']}*pl/ul[0]);
    fpdtype_t cr = sqrt(${c['gamma']}*pr/ur[0]);

    // Inital pressure guess
    fpdtype_t rl = ul[0];
    fpdtype_t rr = ur[0];
    ${pyfr.expand('init_p','rl','vl','pl','cl',
                           'rr','vr','pr','cr','p0')};
    fpdtype_t ud = vr[0] - vl[0];

    // Newton Iterations
%for k in range(kmax):
    ${pyfr.expand('star_flux','p0','pl','rl','cl','fsl','fdl')};
    ${pyfr.expand('star_flux','p0','pr','rr','cr','fsr','fdr')};
    p1 = p0 - (fsl + fsr + ud)/(fdl + fdr);
    p0 = (p1 < 0.) ? ${pmin} : p1;
% endfor
    fpdtype_t us = 0.5*(vl[0] + vr[0] + fsr - fsl);

    // Go through Riemann solve decision tree
    ${pyfr.expand('riemann_decision','rl','vl','pl','cl',
                                     'rr','vr','pr','cr','us','p0','w0')};
    //printf("rs : %E, rl: %E, rr: %E \n",w0[0],rl,rr);
    ${pyfr.expand('primitive_1dflux','w0','nf')};

</%pyfr:macro>

// Transforms to m=[1,0,0]^T, where u[0],u[end] are not modified
// See Moler and Hughes 1999
<%pyfr:macro name='transform_to' params='n,u,t'>

% if ndims == 2:

    t[0] = u[0];
    t[1] =  n[0]*u[1] + n[1]*u[2];
    t[2] = -n[1]*u[1] + n[0]*u[2];
    t[3] = u[3];
    
% elif ndims == 3:

    t[0] = u[0];
    t[4] = u[4];

    if (fabs(n[0]) < ${t_tol}){
        fpdtype_t h = 1./(1. + n[0]);

        t[1] =  n[0]*u[1] + n[1]*u[2] + n[2]*u[3];
    	t[2] = -n[1]*u[1] + (n[0] + h*n[2]*n[2])*u[2] - h*n[1]*n[2]*u[3];
    	t[3] = -n[2]*u[1] - h*n[1]*n[2]*u[2] + (n[0] + h*n[1]*n[1])*u[3];
    }
    else if (fabs(n[1]) < fabs(n[2])){
        fpdtype_t h = 1./(1. - n[1]);
	
        t[1] = n[0]*u[1] + n[1]*u[2] + n[2]*u[3];
	t[2] =  (1. - h*n[0]*n[0])*u[1] + n[0]*u[2] - h*n[0]*n[2]*u[3];
	t[3] = -h*n[0]*n[2]*u[1] + n[2]*u[2] + (1. - h*n[2]*n[2])*u[3];
    }
    else{
       fpdtype_t h = 1./(1. - n[2]);
       
       t[1] = n[0]*u[1] + n[1]*u[2] + n[2]*u[3];
       t[2] = -h*n[0]*n[1]*u[1] + (1. - h*n[1]*n[1])*u[2] + n[1]*u[3];
       t[3] =  (1. - h*n[0]*n[0])*u[1] - h*n[0]*n[1]*u[2] + n[0]*u[3];
    }

% endif
</%pyfr:macro>

// Transforms from m=[1,0,0]^T, where u[0],u[end] are not modified
// See Moler and Hughes 1999
<%pyfr:macro name='transform_from' params='n,t,u'>

% if ndims == 2:

    u[0] = t[0];
    u[1] = n[0]*t[1] - n[1]*t[2];
    u[2] = n[1]*t[1] + n[0]*t[2];
    u[3] = t[3];
    
% elif ndims == 3:

    u[0] =  t[0];
    u[4] =  t[4];

    if (fabs(n[0]) < ${t_tol}){
        fpdtype_t h = 1./(1. + n[0]);

        u[1] =  n[0]*t[1] - n[1]*t[2] - n[2]*t[3];
    	u[2] =  n[1]*t[1] + (n[0] + h*n[2]*n[2])*t[2] - h*n[1]*n[2]*t[3];
    	u[3] =  n[2]*t[1] - h*n[1]*n[2]*t[2] + (n[0] + h*n[1]*n[1])*t[3];
    }
    else if (fabs(n[1]) < fabs(n[2])){
        fpdtype_t h = 1./(1. - n[1]);
	
        u[1] = n[0]*t[1] +  (1. - h*n[0]*n[0])*t[2] - h*n[0]*n[2]*t[3];
	u[2] = n[1]*t[1] + n[0]*t[2] + n[2]*t[3];
	u[3] = n[2]*t[1] - h*n[0]*n[2]*t[2] + (1. - h*n[2]*n[2])*t[3];
    }
    else{
       fpdtype_t h = 1./(1. - n[2]);
       
       u[1] = n[0]*t[1] - h*n[0]*n[1]*t[2] + (1. - h*n[0]*n[0])*t[3];
       u[2] = n[1]*t[1] + (1. - h*n[1]*n[1])*t[2] - h*n[0]*n[1]*t[3];
       u[3] = n[2]*t[1] + n[1]*t[2] + n[0]*t[3];
    }


% endif
</%pyfr:macro>

<%pyfr:macro name='rsolve' params='ul, ur, n, nf'>
    fpdtype_t utl[${nvars}], utr[${nvars}], ntf[${nvars}];

    ${pyfr.expand('transform_to','n', 'ul', 'utl')};
    ${pyfr.expand('transform_to','n', 'ur', 'utr')};

    ${pyfr.expand('rsolve_t1d','utl','utr','ntf')};

    ${pyfr.expand('transform_from','n','ntf','nf')};

</%pyfr:macro>
