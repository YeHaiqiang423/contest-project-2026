function generate_g_fir_vectors()
%GENERATE_G_FIR_VECTORS Bit-true vectors for the symmetric Q1.17 FIR RTL.

    rng(25517, 'twister');
    adc_width = 14;
    fraction_bits = 17;
    num_taps = 255;
    float_coeff = g_design_lowpass(num_taps, 800e3, 20e6, 7.86);
    integer_coeff = round(float_coeff*2^fraction_bits);
    center = (num_taps+1)/2;
    integer_coeff(center) = integer_coeff(center) + ...
        2^fraction_bits-sum(integer_coeff);

    sample_count = 420;
    sample_index = (0:sample_count-1).';
    signal = 5200*sin(2*pi*0.023*sample_index+0.2) + ...
        1300*sin(2*pi*0.071*sample_index-0.8) + ...
        500*sin(2*pi*0.19*sample_index+1.1);
    input_sample = round(signal + 3*randn(sample_count, 1));
    input_sample = min(2^(adc_width-1)-1, max(-2^(adc_width-1), input_sample));
    input_sample(1:8) = [-8192; -8191; -1; 0; 1; 4095; 8190; 8191];

    accumulator = zeros(sample_count, 1, 'int64');
    coeff_int64 = int64(integer_coeff(:));
    input_int64 = int64(input_sample(:));
    for n = 1:sample_count
        first_tap = max(1, n-num_taps+1);
        input_slice = input_int64(n:-1:first_tap);
        accumulator(n) = sum(input_slice.*coeff_int64(1:numel(input_slice)));
    end
    rounded = floor((double(accumulator)+2^(fraction_bits-1))/2^fraction_bits);
    expected_sample = min(32767, max(-32768, rounded));

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    vector_path = fullfile(vector_dir, 'g_fir_vectors.txt');
    file_id = fopen(vector_path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', vector_path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d %d\n', [input_sample expected_sample].');
    fprintf('Generated %d bit-true FIR vectors in %s\n', sample_count, vector_path);
end
