function generate_g_phase_vectors()
%GENERATE_G_PHASE_VECTORS Bit-true vectors for the harmonic phase estimator.
%   The contest defines every component as
%       A_h*sin(2*pi*h*f0*t + phi_h).
%   Therefore the estimator uses C=sum(x*cos), S=sum(x*sin), and
%   phi_h=atan2(C,S).  Displayed harmonic phase is
%       wrap(phi_h-h*phi_1, 0, 360 degrees).
%
%   g_phase_input.txt contains concatenated, signed decimal, 4096-sample
%   frames after exactly one Q1.15 Hann multiplication.  Each base case is
%   repeated twice so an RTL test can exercise consecutive-frame behavior.
%   g_phase_config.txt fields are:
%       case_id repeat_index component_count f0_hz f1_hz f2_hz
%   g_phase_expected.txt fields are:
%       case_id repeat_index fundamental_phase_deg x0_phase_deg x1_phase_deg
%   Missing or non-harmonic outputs use the UART sentinel 999.

    nfft = 4096;
    sample_rate_hz = 2e6;
    harmonic_tolerance_hz = 500;
    invalid_phase = 999;
    repeat_count = 2;
    n = (0:nfft-1).';

    hann_q15 = int64(round((0.5-0.5*cos(2*pi*n/(nfft-1)))*32767));

    cases = struct('name', {}, 'frequency_hz', {}, 'amplitude_code', {}, ...
        'phase_deg', {}, 'sample_shift', {});
    cases(end+1) = make_case('zero_phase', ...
        [100000 200000 400000], [800 500 300], [0 0 0], 0);
    cases(end+1) = make_case('weak_fundamental', ...
        [100000 200000 400000], [100 400 500], [100 40 0], 0);
    cases(end+1) = make_case('off_bin_orders_1_3_5', ...
        [73250 219750 366250], [700 350 220], [-35 80 170], 0);
    cases(end+1) = make_case('phase_wrap', ...
        [62500 125000 250000], [900 600 350], [10 19 41], 0);
    cases(end+1) = make_case('phase_wrap_shift_37', ...
        [62500 125000 250000], [900 600 350], [10 19 41], 37);
    cases(end+1) = make_case('two_components_order_3', ...
        [80000 240000], [800 320], [25 -70], 0);
    cases(end+1) = make_case('non_harmonic', ...
        [100000 230000 370000], [800 350 220], [10 70 -100], 0);
    cases(end+1) = make_case('single_tone', ...
        125000, 800, 137, 0);
    cases(end+1) = make_case('mixed_validity', ...
        [100000 230000 400000], [1000 500 350], [10 70 250], 0);

    frame_count = numel(cases)*repeat_count;
    input_samples = zeros(frame_count*nfft, 1);
    frame_config = zeros(frame_count, 6);
    frame_expected = zeros(frame_count, 5);

    fprintf('\n4096-point sine-phase estimator vectors\n');
    fprintf('%-26s %5s %5s %5s %10s %10s\n', ...
        'case', 'count', 'x0', 'x1', 'projected0', 'projected1');

    frame_index = 0;
    for case_index = 1:numel(cases)
        definition = cases(case_index);
        validate_case(definition, sample_rate_hz);

        raw_samples = synthesize_case(definition, n, sample_rate_hz);
        windowed_samples = apply_q15_hann(raw_samples, hann_q15);
        expected_phase = expected_relative_phase(definition, ...
            harmonic_tolerance_hz, invalid_phase);
        projected_phase = measure_relative_phase(windowed_samples, ...
            definition.frequency_hz, sample_rate_hz, ...
            harmonic_tolerance_hz, invalid_phase);

        for output_index = 1:2
            if expected_phase(output_index) == invalid_phase
                assert(projected_phase(output_index) == invalid_phase, ...
                    '%s output %d should be invalid.', ...
                    definition.name, output_index-1);
            else
                assert(projected_phase(output_index) == ...
                    expected_phase(output_index), ...
                    ['%s output %d projection rounded to %d degrees; ' ...
                    'expected %d degrees.'], definition.name, output_index-1, ...
                    projected_phase(output_index), ...
                    expected_phase(output_index));
            end
        end

        fprintf('%-26s %5d %5d %5d %10d %10d\n', definition.name, ...
            numel(definition.frequency_hz), expected_phase(1), ...
            expected_phase(2), projected_phase(1), projected_phase(2));

        padded_frequency = zeros(1, 3);
        padded_frequency(1:numel(definition.frequency_hz)) = ...
            definition.frequency_hz;
        for repeat_index = 0:repeat_count-1
            sample_first = frame_index*nfft+1;
            sample_last = sample_first+nfft-1;
            input_samples(sample_first:sample_last) = windowed_samples;
            frame_config(frame_index+1, :) = [case_index-1 repeat_index ...
                numel(definition.frequency_hz) padded_frequency];
            frame_expected(frame_index+1, :) = [case_index-1 repeat_index ...
                0 expected_phase];
            frame_index = frame_index+1;
        end
    end

    sine_q15 = round(sin(2*pi*n/nfft)*2^15);
    sine_q15 = min(2^15-1, max(-2^15, sine_q15));
    assert(sine_q15(1) == 0 && sine_q15(nfft/4+1) == 32767 && ...
        sine_q15(nfft/2+1) == 0 && sine_q15(3*nfft/4+1) == -32768, ...
        'Q1.15 sine ROM quadrant anchors are incorrect.');

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    write_decimal(fullfile(vector_dir, 'g_phase_input.txt'), input_samples);
    write_rows(fullfile(vector_dir, 'g_phase_config.txt'), frame_config, ...
        '%d %d %d %d %d %d\n');
    write_rows(fullfile(vector_dir, 'g_phase_expected.txt'), frame_expected, ...
        '%d %d %d %d %d\n');
    write_hex16(fullfile(vector_dir, 'g_sine_q15_4096.hex'), sine_q15);

    fprintf(['Generated %d phase frames (%d base cases repeated %d times), ' ...
        '%d signed Hann-windowed samples and a 4096-entry Q1.15 sine ROM.\n'], ...
        frame_count, numel(cases), repeat_count, numel(input_samples));
end

function definition = make_case(name, frequency_hz, amplitude_code, ...
        phase_deg, sample_shift)
    definition = struct('name', name, ...
        'frequency_hz', double(frequency_hz(:).'), ...
        'amplitude_code', double(amplitude_code(:).'), ...
        'phase_deg', double(phase_deg(:).'), ...
        'sample_shift', double(sample_shift));
end

function validate_case(definition, sample_rate_hz)
    component_count = numel(definition.frequency_hz);
    assert(component_count >= 1 && component_count <= 3, ...
        '%s must contain one to three components.', definition.name);
    assert(numel(definition.amplitude_code) == component_count && ...
        numel(definition.phase_deg) == component_count, ...
        '%s definition vectors have different lengths.', definition.name);
    assert(all(diff(definition.frequency_hz) > 0), ...
        '%s frequencies must be in ascending order.', definition.name);
    assert(all(definition.frequency_hz > 0) && ...
        all(definition.frequency_hz < sample_rate_hz/2), ...
        '%s contains a frequency outside the positive Nyquist band.', ...
        definition.name);
end

function samples = synthesize_case(definition, n, sample_rate_hz)
    samples = zeros(size(n));
    shifted_n = n+definition.sample_shift;
    for component_index = 1:numel(definition.frequency_hz)
        samples = samples+definition.amplitude_code(component_index)*sin( ...
            2*pi*definition.frequency_hz(component_index)*shifted_n/ ...
            sample_rate_hz+deg2rad(definition.phase_deg(component_index)));
    end
    samples = round(samples);
    assert(max(abs(samples)) <= 32767, ...
        '%s input exceeds signed 16-bit range.', definition.name);
end

function output = apply_q15_hann(input, hann_q15)
    product = int64(input(:)).*hann_q15;
    output = floor((double(product)+2^14)/2^15);
end

function phase_output = expected_relative_phase(definition, ...
        harmonic_tolerance_hz, invalid_phase)
    phase_output = invalid_phase*ones(1, 2);
    fundamental_hz = definition.frequency_hz(1);
    fundamental_phase_deg = definition.phase_deg(1);
    for component_index = 2:numel(definition.frequency_hz)
        harmonic_order = round(definition.frequency_hz(component_index)/ ...
            fundamental_hz);
        frequency_error_hz = abs(definition.frequency_hz(component_index)- ...
            harmonic_order*fundamental_hz);
        if harmonic_order >= 2 && ...
                frequency_error_hz <= harmonic_tolerance_hz
            relative_phase_deg = mod(definition.phase_deg(component_index)- ...
                harmonic_order*fundamental_phase_deg, 360);
            phase_output(component_index-1) = mod(round(relative_phase_deg), 360);
        end
    end
end

function phase_output = measure_relative_phase(samples, frequency_hz, ...
        sample_rate_hz, harmonic_tolerance_hz, invalid_phase)
    n = (0:numel(samples)-1).';
    absolute_phase_deg = zeros(size(frequency_hz));
    for component_index = 1:numel(frequency_hz)
        angle_rad = 2*pi*frequency_hz(component_index)*n/sample_rate_hz;
        cosine_projection = sum(double(samples).*cos(angle_rad));
        sine_projection = sum(double(samples).*sin(angle_rad));
        absolute_phase_deg(component_index) = mod( ...
            atan2d(cosine_projection, sine_projection), 360);
    end

    phase_output = invalid_phase*ones(1, 2);
    fundamental_hz = frequency_hz(1);
    for component_index = 2:numel(frequency_hz)
        harmonic_order = round(frequency_hz(component_index)/fundamental_hz);
        frequency_error_hz = abs(frequency_hz(component_index)- ...
            harmonic_order*fundamental_hz);
        if harmonic_order >= 2 && ...
                frequency_error_hz <= harmonic_tolerance_hz
            relative_phase_deg = mod(absolute_phase_deg(component_index)- ...
                harmonic_order*absolute_phase_deg(1), 360);
            phase_output(component_index-1) = mod(round(relative_phase_deg), 360);
        end
    end
end

function write_decimal(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end

function write_rows(path, values, format_text)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, format_text, values.');
end

function write_hex16(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    unsigned_values = mod(double(values(:)), 2^16);
    fprintf(file_id, '%04X\n', unsigned_values);
end
