function analyze_g_fixed_fir()
%ANALYZE_G_FIXED_FIR Quantize the 20 MSPS low-pass and enforce its budget.

    fs_hz = 20e6;
    num_taps = 255;
    cutoff_hz = 750e3;
    beta = 7.86;
    coefficient_fraction_bits = 17;
    adc_width = 14;
    fft_length = 2^20;

    float_coeff = g_design_lowpass(num_taps, cutoff_hz, fs_hz, beta);
    scale = 2^coefficient_fraction_bits;
    integer_coeff = round(float_coeff*scale);
    center = (num_taps+1)/2;
    integer_coeff(center) = integer_coeff(center) + scale-sum(integer_coeff);
    fixed_coeff = integer_coeff/scale;

    response = fft(fixed_coeff, fft_length);
    response = response(1:fft_length/2+1);
    frequency_hz = (0:fft_length/2).'*fs_hz/fft_length;
    response_db = 20*log10(max(abs(response(:)), 1e-15));
    passband = frequency_hz <= 500e3;
    stopband = frequency_hz >= 1e6;
    passband_ripple_db = max(response_db(passband))-min(response_db(passband));
    gain_500k_db = response_db(find(frequency_hz <= 500e3, 1, 'last'));
    worst_stopband_db = max(response_db(stopband));

    max_adc_magnitude = 2^(adc_width-1);
    accumulator_magnitude = double(sum(abs(int64(integer_coeff))))*max_adc_magnitude;
    accumulator_bits = ceil(log2(accumulator_magnitude+1))+1;
    symmetry_error = max(abs(integer_coeff-fliplr(integer_coeff)));

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    result_dir = fullfile(project_root, 'results');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    if ~exist(result_dir, 'dir'), mkdir(result_dir); end

    coefficient_path = fullfile(vector_dir, 'g_lpf_q17_coefficients.txt');
    coefficient_file = fopen(coefficient_path, 'w');
    assert(coefficient_file >= 0, 'Cannot open %s.', coefficient_path);
    coefficient_cleanup = onCleanup(@() fclose(coefficient_file)); %#ok<NASGU>
    fprintf(coefficient_file, '%d\n', integer_coeff);

    unique_hex_path = fullfile(vector_dir, 'g_lpf_q17_unique.hex');
    unique_hex_file = fopen(unique_hex_path, 'w');
    assert(unique_hex_file >= 0, 'Cannot open %s.', unique_hex_path);
    unique_hex_cleanup = onCleanup(@() fclose(unique_hex_file)); %#ok<NASGU>
    unique_coeff = integer_coeff(1:center);
    unsigned_coeff = mod(unique_coeff, 2^18);
    fprintf(unique_hex_file, '%05X\n', unsigned_coeff);

    report_path = fullfile(result_dir, 'g_fixed_fir_analysis.txt');
    report_file = fopen(report_path, 'w');
    assert(report_file >= 0, 'Cannot open %s.', report_path);
    report_cleanup = onCleanup(@() fclose(report_file)); %#ok<NASGU>
    report = sprintf([ ...
        'sample_rate_hz=%d\nnum_taps=%d\ncutoff_hz=%d\n' ...
        'coefficient_format=Q1.%d_signed\npassband_ripple_db=%.9f\n' ...
        'gain_500khz_db=%.9f\nworst_stopband_db=%.9f\n' ...
        'accumulator_bits=%d\nsymmetry_error_lsb=%d\n'], ...
        fs_hz, num_taps, cutoff_hz, coefficient_fraction_bits, ...
        passband_ripple_db, gain_500k_db, worst_stopband_db, ...
        accumulator_bits, symmetry_error);
    fprintf(report_file, '%s', report);
    fprintf('%s', report);
    fprintf('coefficient_file=%s\n', coefficient_path);
    fprintf('unique_hex_file=%s\n', unique_hex_path);
    fprintf('report_file=%s\n', report_path);

    assert(max(abs(integer_coeff)) < 2^17, 'Coefficient exceeds signed 18-bit range.');
    assert(symmetry_error == 0, 'Quantized coefficient symmetry was lost.');
    assert(passband_ripple_db <= 0.05, 'Passband ripple exceeds 0.05 dB.');
    assert(worst_stopband_db <= -60, 'Stopband attenuation is below 60 dB.');
    assert(accumulator_bits <= 32, 'FIR accumulator needs more than 32 bits.');
    fprintf('PASS: fixed FIR satisfies the provisional digital filter budget.\n');
end
