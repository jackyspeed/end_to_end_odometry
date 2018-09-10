syms dt m_fcx m_fcy m_fcz m_fcyaw m_fcpitch m_fcroll m_wx m_wy m_wz m_ax m_ay m_az real % Measurement & control inputs
syms s_dpx s_dpy s_dpz s_dvx s_dvy s_dvz s_dthetax s_dthetay s_dthetaz s_dbax s_dbay s_dbaz s_dbwx s_dbwy s_dbwz s_dgx s_dgy s_dgz s_real % error state
syms ns_px ns_py ns_pz ns_vx ns_vy ns_vz ns_qw ns_qx ns_qy ns_qz ns_bax ns_bay ns_baz ns_bwx ns_bwy ns_bwz ns_gx ns_gy ns_gz real % nominal state
syms cov_a cov_w cov_ba cov_bw
  
% Measurements and inputs
am = [m_ax m_ay m_az].';
wm = [m_wx m_wy m_wz].';

imu_meas = [am; wm];

% Error state variables
s_dp = [s_dpx s_dpy s_dpz].';
s_dv = [s_dvx s_dvy s_dvz].';
s_dtheta = [s_dthetax, s_dthetay, s_dthetaz].';
s_dba = [s_dbax s_dbay s_dbaz].';
s_dbg = [s_dbwx s_dbwy s_dbwz].';
s_dg = [s_dgx s_dgy s_dgz].';
g0 = [0 0 -9.80665].';

% Nominal variables
ns_p = [ns_px, ns_py, ns_pz].';
ns_v = [ns_vx, ns_vy, ns_vz].';
ns_q = [ns_qw, ns_qx, ns_qy, ns_qz].';
ns_ba = [ns_bax, ns_bay, ns_baz].';
ns_bw = [ns_bwx, ns_bwy, ns_bwz].';
ns_g = g0;

% nominal states
ns_p_kp1 = ns_p + ns_v * dt + 0.5 * dt^2 * (R_quat(ns_q) * (am - ns_ba) + ns_g);
ns_v_kp1 = ns_v + dt * (R_quat(ns_q) * (am - ns_ba) + ns_g);
ns_q_kp1 = mul_q(ns_q, q_v((wm - ns_bw)*dt));
ns_ba_kp1 = ns_ba;
ns_bw_kp1 = ns_bw;
% ns_g_kp1 = ns_g;

f_nom = [ns_p_kp1; ns_v_kp1; ns_q_kp1; ns_ba_kp1; ns_bw_kp1];
x_nom = [ns_p; ns_v; ns_q; ns_ba; ns_bw];
h_nom = [ns_p];
H_nom = eval(jacobian(h_nom, x_nom)); % dh_dom / dx_nom

f_nom_func = matlabFunction(f_nom, 'Vars', {[x_nom; imu_meas; dt]});
h_nom_func = matlabFunction(h_nom, 'Vars', {x_nom});

% error state KF
Fx = sym(zeros(15,15));
Fx(1:3,1:3) = eye(3,3);
Fx(1:3,4:6) = eye(3,3) * dt;
Fx(4:6,4:6) = eye(3,3);
Fx(4:6,7:9) = -R_quat(ns_q) * skew(am - ns_ba) * dt;
Fx(4:6,10:12) = -R_quat(ns_q) * dt;
Fx(7:9,7:9) = R_v((wm - ns_bw)*dt).';
Fx(7:9,13:15) = -eye(3,3)*dt;
Fx(10:15,10:15) = eye(6, 6);

Fi = zeros(15, 12);
Fi(4:15,1:12) = eye(12, 12);

Qi = sym(zeros(12, 12));
Qi(1:3,1:3) = cov_a * dt^2 * eye(3, 3);
Qi(4:6,4:6) = cov_w * dt^2 * eye(3, 3);
Qi(7:9,7:9) = cov_ba * dt * eye(3, 3);
Qi(10:12,10:12) = cov_bw * dt * eye(3, 3);

x_es = [s_dp; s_dv; s_dtheta; s_dba; s_dbg];
cov_p = [cov_a; cov_w; cov_ba; cov_bw];

G = sym(eye(15, 15));
G(7:9, 7:9) = eye(3,3) - skew(0.5 * s_dtheta); 

Fx_func = matlabFunction(Fx, 'Vars', {[x_nom; x_es; imu_meas; dt]});
Qi_func = matlabFunction(Qi, 'Vars', {[cov_p; dt]});
G_func = matlabFunction(G, 'Vars', {x_es});

% injecting error state into nominal
f_nom_corr = sym(zeros(16, 1));
f_nom_corr(1:6) = x_nom(1:6) + x_es(1:6);
f_nom_corr(11:16) = x_nom(11:16) + x_es(10:15);
f_nom_corr(7:10) = mul_q(x_nom(7:10), q_v(x_es(7:9)));

H_es = jacobian(f_nom_corr, x_es); % dx_nom / x_xes
H_es = limit(limit(limit(H_es,s_dthetax,0), s_dthetay, 0), s_dthetaz, 0);

H_es_func = matlabFunction(H_es, 'Vars', {x_nom});
f_nom_corr_func = matlabFunction(f_nom_corr, 'Vars', {[x_nom; x_es]});


