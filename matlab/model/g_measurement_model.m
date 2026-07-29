function result = g_measurement_model(adc_samples_v, fs_adc_hz, cfg)
%G_MEASUREMENT_MODEL Floating-point golden model for the 2026 G problem.
%   Voltages use volts, frequencies use hertz, and reported component
%   amplitudes are sine peak values. The first /10 operation assumes the
%   board analog filter prevents aliasing into the 0--500 kHz wanted band.

    if nargin < 3
        cfg = struct();
    end
    cfg = set_default(cfg, 'decim_stage1', 10);
    cfg = set_default(cfg, 'decim_stage2', 10);
    cfg = set_default(cfg, 'fir_taps', 255);
    cfg = set_default(cfg, 'fir_cutoff_hz', 750e3);
    cfg = set_default(cfg, 'fir_kaiser_beta', 7.86);
    cfg = set_default(cfg, 'nfft', 4096);
    cfg = set_default(cfg, 'min_frequency_hz', 10e3);
    cfg = set_default(cfg, 'max_frequency_hz', 500e3);
    cfg = set_default(cfg, 'max_components', 3);
    cfg = set_default(cfg, 'peak_threshold_ratio', 0.02);
    cfg = set_default(cfg, 'waveform_points', 512);

    x_adc = double(adc_samples_v(:));
    fs_mid_hz = fs_adc_hz / cfg.decim_stage1;
    fs_fft_hz = fs_mid_hz / cfg.decim_stage2;
    if abs(fs_mid_hz - 20e6) > 1
        error('Expected a 20 MSPS intermediate rate, got %.3f Hz.', fs_mid_hz);
    end
    required_mid_samples = cfg.nfft*cfg.decim_stage2 + cfg.fir_taps;
    if required_mid_samples > numel(x_adc)/cfg.decim_stage1
        error('Not enough ADC samples for filter settling and one FFT frame.');
    end

    x_mid_in = x_adc(1:cfg.decim_stage1:end);
    fir_coeff = g_design_lowpass(cfg.fir_taps, cfg.fir_cutoff_hz, ...
        fs_mid_hz, cfg.fir_kaiser_beta);
    x_mid = filter(fir_coeff, 1, x_mid_in);
    x_mid = x_mid(cfg.fir_taps:end);

    x_fft_rate = x_mid(1:cfg.decim_stage2:end);
    frame = x_fft_rate(end-cfg.nfft+1:end);
    frame = frame - mean(frame);
    n = (0:cfg.nfft-1).';
    hann_window = 0.5 - 0.5*cos(2*pi*n/(cfg.nfft-1));
    fft_windowed = fft(frame.*hann_window);
    half_bins = (0:floor(cfg.nfft/2)).';
    detect_magnitude = abs(fft_windowed(half_bins+1));
    frequency_axis_hz = half_bins*fs_fft_hz/cfg.nfft;

    peak_bins = select_spectral_peaks(detect_magnitude, frequency_axis_hz, cfg);
    component_frequency_hz = zeros(numel(peak_bins), 1);
    for k = 1:numel(peak_bins)
        component_frequency_hz(k) = refine_peak_frequency( ...
            detect_magnitude, peak_bins(k), fs_fft_hz, cfg.nfft);
    end
    component_frequency_hz = sort(component_frequency_hz);

    sample_time_s = (0:cfg.nfft-1).'/fs_fft_hz;
    fit_matrix = ones(cfg.nfft, 2*numel(component_frequency_hz)+1);
    for k = 1:numel(component_frequency_hz)
        omega_t = 2*pi*component_frequency_hz(k)*sample_time_s;
        fit_matrix(:, 2*k-1) = cos(omega_t);
        fit_matrix(:, 2*k) = sin(omega_t);
    end
    fit_coeff = fit_matrix\frame;

    component_amplitude_v = zeros(numel(component_frequency_hz), 1);
    component_phase_rad = zeros(numel(component_frequency_hz), 1);
    for k = 1:numel(component_frequency_hz)
        cosine_coeff = fit_coeff(2*k-1);
        sine_coeff = fit_coeff(2*k);
        filtered_amplitude = hypot(cosine_coeff, sine_coeff);
        response = fir_response_at(fir_coeff, component_frequency_hz(k), fs_mid_hz);
        component_amplitude_v(k) = filtered_amplitude/max(abs(response), eps);
        component_phase_rad(k) = atan2(-sine_coeff, cosine_coeff);
    end

    fundamental_hz = component_frequency_hz(1);
    dense_phase = linspace(0, 2*pi, 8193).';
    reconstructed_period_v = reconstruct_waveform(dense_phase, ...
        component_frequency_hz, component_amplitude_v, component_phase_rad);
    upp_v = max(reconstructed_period_v)-min(reconstructed_period_v);
    urms_v = sqrt(sum(component_amplitude_v.^2)/2);

    one_period_phase = linspace(0, 2*pi, cfg.waveform_points+1).';
    one_period_phase(end) = [];
    waveform_one_period_v = reconstruct_waveform(one_period_phase, ...
        component_frequency_hz, component_amplitude_v, component_phase_rad);
    three_period_phase = linspace(0, 6*pi, 3*cfg.waveform_points+1).';
    three_period_phase(end) = [];
    waveform_three_period_v = reconstruct_waveform(three_period_phase, ...
        component_frequency_hz, component_amplitude_v, component_phase_rad);

    coherent_gain = mean(hann_window);
    spectrum_amplitude_v = 2*detect_magnitude/(cfg.nfft*coherent_gain);
    spectrum_amplitude_v(1) = spectrum_amplitude_v(1)/2;
    if rem(cfg.nfft, 2) == 0
        spectrum_amplitude_v(end) = spectrum_amplitude_v(end)/2;
    end

    result = struct();
    result.component_frequency_hz = component_frequency_hz;
    result.component_amplitude_v = component_amplitude_v;
    result.component_phase_rad = component_phase_rad;
    result.fundamental_hz = fundamental_hz;
    result.upp_v = upp_v;
    result.urms_v = urms_v;
    result.waveform_one_period_v = waveform_one_period_v;
    result.waveform_three_period_v = waveform_three_period_v;
    result.spectrum_frequency_hz = frequency_axis_hz;
    result.spectrum_amplitude_v = spectrum_amplitude_v;
    result.fs_mid_hz = fs_mid_hz;
    result.fs_fft_hz = fs_fft_hz;
    result.fft_resolution_hz = fs_fft_hz/cfg.nfft;
    result.fir_coeff = fir_coeff(:);
end

function cfg = set_default(cfg, field_name, value)
    if ~isfield(cfg, field_name)
        cfg.(field_name) = value;
    end
end

function peak_bins = select_spectral_peaks(magnitude, frequency_hz, cfg)
    valid = frequency_hz >= cfg.min_frequency_hz & ...
        frequency_hz <= cfg.max_frequency_hz;
    local_peak = false(size(magnitude));
    local_peak(2:end-1) = magnitude(2:end-1) >= magnitude(1:end-2) & ...
        magnitude(2:end-1) > magnitude(3:end);
    candidate_bins = find(valid & local_peak);
    if isempty(candidate_bins)
        error('No spectral component detected in the measurement band.');
    end
    candidate_values = magnitude(candidate_bins);
    [candidate_values, order] = sort(candidate_values, 'descend');
    candidate_bins = candidate_bins(order);
    noise_floor = median(magnitude(valid));
    threshold = max(candidate_values(1)*cfg.peak_threshold_ratio, 8*noise_floor);

    selected = zeros(cfg.max_components, 1);
    selected_count = 0;
    for k = 1:numel(candidate_bins)
        if candidate_values(k) < threshold
            break;
        end
        if selected_count == 0 || ...
                all(abs(candidate_bins(k)-selected(1:selected_count)) >= 6)
            selected_count = selected_count+1;
            selected(selected_count) = candidate_bins(k);
            if selected_count == cfg.max_components
                break;
            end
        end
    end
    peak_bins = selected(1:selected_count);
end

function frequency_hz = refine_peak_frequency(magnitude, matlab_bin, fs_hz, nfft)
    y_left = log(max(magnitude(matlab_bin-1), realmin));
    y_mid = log(max(magnitude(matlab_bin), realmin));
    y_right = log(max(magnitude(matlab_bin+1), realmin));
    denominator = y_left-2*y_mid+y_right;
    if abs(denominator) < eps
        fractional_offset = 0;
    else
        fractional_offset = 0.5*(y_left-y_right)/denominator;
        fractional_offset = max(-0.5, min(0.5, fractional_offset));
    end
    frequency_hz = (matlab_bin-1+fractional_offset)*fs_hz/nfft;
end

function response = fir_response_at(coeff, frequency_hz, fs_hz)
    tap_index = 0:numel(coeff)-1;
    response = sum(coeff.*exp(-1j*2*pi*frequency_hz*tap_index/fs_hz));
end

function waveform = reconstruct_waveform(phase, frequencies, amplitudes, phases)
    waveform = zeros(size(phase));
    fundamental_hz = frequencies(1);
    for k = 1:numel(frequencies)
        waveform = waveform + amplitudes(k)*cos( ...
            frequencies(k)/fundamental_hz*phase+phases(k));
    end
end
