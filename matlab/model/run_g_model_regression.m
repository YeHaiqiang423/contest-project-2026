function run_g_model_regression()
%RUN_G_MODEL_REGRESSION Exercise all three tasks and enforce contest limits.

    rng(20260729, 'twister');
    fs_adc_hz = 200e6;
    duration_s = 2.8e-3;
    adc_full_scale_vpp = 2.0;
    adc_bits = 14;

    cases = struct('name', {}, 'task', {}, 'f0_hz', {}, 'orders', {}, ...
        'relative_amplitudes', {}, 'phases_rad', {}, 'target_upp_v', {}, ...
        'interference_hz', {});
    cases(end+1) = make_case('T1_low', 1, 10.5e3, [1 2 3], ...
        [1.0 0.28 0.13], [0.1 1.2 -0.8], 0.100, 0);
    cases(end+1) = make_case('T1_upper', 1, 40e3, [1 3 5], ...
        [1.0 0.22 0.11], [-0.5 0.8 2.0], 0.250, 0);
    cases(end+1) = make_case('T2_min_pp', 2, 73.25e3, [1 2], ...
        [1.0 0.35], [0.3 -1.0], 0.050, 0);
    cases(end+1) = make_case('T2_500k', 2, 100e3, [1 3 5], ...
        [1.0 0.20 0.10], [-0.9 0.4 1.7], 0.250, 0);
    cases(end+1) = make_case('T2_f0_250k', 2, 250e3, [1 2], ...
        [1.0 0.16], [0.7 -1.3], 0.180, 0);
    cases(end+1) = make_case('T3_1MHz', 3, 62.5e3, [1 2 4], ...
        [1.0 0.24 0.12], [0.2 -0.6 1.4], 0.160, 1.0e6);
    cases(end+1) = make_case('T3_1p37MHz', 3, 91.75e3, [1 2 5], ...
        [1.0 0.30 0.09], [-0.4 1.0 2.1], 0.220, 1.37e6);
    cases(end+1) = make_case('T3_5MHz', 3, 100e3, [1 3 5], ...
        [1.0 0.18 0.10], [0.6 -1.2 0.9], 0.080, 5.0e6);

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    output_dir = fullfile(project_root, 'results');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    csv_path = fullfile(output_dir, 'g_model_regression.csv');
    csv_file = fopen(csv_path, 'w');
    if csv_file < 0
        error('Cannot open %s for writing.', csv_path);
    end
    cleanup = onCleanup(@() fclose(csv_file)); %#ok<NASGU>
    fprintf(csv_file, ['case,task,component_count,f0_error_hz,' ...
        'max_frequency_error_hz,max_amplitude_error_mv,upp_error_mv,' ...
        'rms_error_mv,pass\n']);

    fprintf('\n2026 G floating-point measurement regression\n');
    fprintf('FFT rate: 2 MSPS, NFFT: 4096, resolution: %.5f Hz\n\n', 2e6/4096);
    fprintf('%-14s %4s %7s %10s %11s %11s %10s %10s %6s\n', ...
        'case', 'task', 'count', 'f0_err', 'freq_err', 'amp_err', ...
        'upp_err', 'rms_err', 'pass');

    all_pass = true;
    for case_index = 1:numel(cases)
        definition = cases(case_index);
        [wanted_signal_v, truth] = synthesize_wanted(definition, fs_adc_hz, duration_s);
        sample_count = numel(wanted_signal_v);
        time_s = (0:sample_count-1).'/fs_adc_hz;
        measured_input_v = wanted_signal_v+1.5e-3;
        if definition.interference_hz > 0
            measured_input_v = measured_input_v + ...
                0.100*sin(2*pi*definition.interference_hz*time_s+0.37);
        end
        adc_lsb_v = adc_full_scale_vpp/(2^adc_bits);
        measured_input_v = measured_input_v + 0.20*adc_lsb_v*randn(sample_count, 1);
        adc_samples_v = quantize_adc(measured_input_v, adc_full_scale_vpp, adc_bits);

        result = g_measurement_model(adc_samples_v, fs_adc_hz);
        count_ok = numel(result.component_frequency_hz) == numel(truth.frequency_hz);
        if count_ok
            frequency_error_hz = abs(result.component_frequency_hz-truth.frequency_hz);
            amplitude_error_mv = 1e3*abs(result.component_amplitude_v-truth.amplitude_v);
            max_frequency_error_hz = max(frequency_error_hz);
            max_amplitude_error_mv = max(amplitude_error_mv);
        else
            max_frequency_error_hz = inf;
            max_amplitude_error_mv = inf;
        end
        f0_error_hz = abs(result.fundamental_hz-truth.frequency_hz(1));
        upp_error_mv = 1e3*abs(result.upp_v-truth.upp_v);
        rms_error_mv = 1e3*abs(result.urms_v-truth.urms_v);
        case_pass = count_ok && f0_error_hz <= 1e3 && ...
            max_frequency_error_hz <= 1e3 && max_amplitude_error_mv <= 5 && ...
            upp_error_mv <= 5 && rms_error_mv <= 5;
        all_pass = all_pass && case_pass;

        fprintf('%-14s %4d %7d %10.2f %11.2f %11.3f %10.3f %10.3f %6s\n', ...
            definition.name, definition.task, numel(result.component_frequency_hz), ...
            f0_error_hz, max_frequency_error_hz, max_amplitude_error_mv, ...
            upp_error_mv, rms_error_mv, pass_text(case_pass));
        fprintf(csv_file, '%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%d\n', ...
            definition.name, definition.task, numel(result.component_frequency_hz), ...
            f0_error_hz, max_frequency_error_hz, max_amplitude_error_mv, ...
            upp_error_mv, rms_error_mv, case_pass);
    end

    fprintf('\nCSV: %s\n', csv_path);
    if ~all_pass
        error('Golden-model regression failed one or more contest limits.');
    end
    fprintf('PASS: all golden-model cases satisfy the numerical limits.\n');
end

function definition = make_case(name, task, f0_hz, orders, relative_amplitudes, ...
        phases_rad, target_upp_v, interference_hz)
    definition = struct('name', name, 'task', task, 'f0_hz', f0_hz, ...
        'orders', orders(:), 'relative_amplitudes', relative_amplitudes(:), ...
        'phases_rad', phases_rad(:), 'target_upp_v', target_upp_v, ...
        'interference_hz', interference_hz);
end

function [signal_v, truth] = synthesize_wanted(definition, fs_hz, duration_s)
    dense_phase = linspace(0, 2*pi, 100001).';
    normalized = zeros(size(dense_phase));
    for k = 1:numel(definition.orders)
        normalized = normalized + definition.relative_amplitudes(k)*sin( ...
            definition.orders(k)*dense_phase+definition.phases_rad(k));
    end
    scale = definition.target_upp_v/(max(normalized)-min(normalized));
    amplitude_v = scale*definition.relative_amplitudes;

    sample_count = floor(duration_s*fs_hz);
    time_s = (0:sample_count-1).'/fs_hz;
    signal_v = zeros(sample_count, 1);
    for k = 1:numel(definition.orders)
        signal_v = signal_v + amplitude_v(k)*sin( ...
            2*pi*definition.orders(k)*definition.f0_hz*time_s + ...
            definition.phases_rad(k));
    end
    truth = struct();
    truth.frequency_hz = definition.orders*definition.f0_hz;
    truth.amplitude_v = amplitude_v;
    truth.upp_v = definition.target_upp_v;
    truth.urms_v = sqrt(sum(amplitude_v.^2)/2);
end

function quantized_v = quantize_adc(input_v, full_scale_vpp, bits)
    positive_limit_v = full_scale_vpp/2;
    lsb_v = full_scale_vpp/(2^bits);
    clipped_v = min(positive_limit_v-lsb_v, max(-positive_limit_v, input_v));
    quantized_v = round(clipped_v/lsb_v)*lsb_v;
end

function value = pass_text(flag)
    if flag
        value = 'PASS';
    else
        value = 'FAIL';
    end
end
