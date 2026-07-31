function generate_g_pipeline_vectors()
%GENERATE_G_PIPELINE_VECTORS End-to-end bit-true vectors before the FFT core.

    rng(200204096, 'twister');
    adc_decimation = 10;
    frame_decimation = 4;
    frame_length = 16;
    raw_count = adc_decimation*frame_decimation*frame_length;
    raw_index = (0:raw_count-1).';

    raw_signed = round(2200*sin(2*pi*460e3*raw_index/200e6+0.2) + ...
        700*sin(2*pi*1.42e6*raw_index/200e6-0.7) + ...
        4*randn(raw_count, 1));
    raw_signed(1:8) = [-8192; -4096; -1; 0; 1; 2048; 4095; 8191];
    raw_signed = min(8191, max(-8192, raw_signed));
    raw_twos_code = mod(raw_signed, 2^14);

    samples_20m = raw_signed(1:adc_decimation:end);
    fir_float = g_design_lowpass(255, 800e3, 20e6, 7.86);
    fir_q17 = round(fir_float*2^17);
    fir_q17(128) = fir_q17(128)+2^17-sum(fir_q17);
    fir_output = fixed_fir(samples_20m, fir_q17, 17);
    frame_samples = fir_output(1:frame_decimation:end);

    hann_index = (0:frame_length-1).';
    hann_q15 = round((0.5-0.5*cos(2*pi*hann_index/(frame_length-1)))*32767);
    window_product = int64(frame_samples).*int64(hann_q15);
    fft_expected = floor((double(window_product)+2^14)/2^15);

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end
    write_vector(fullfile(vector_dir, 'g_pipeline_adc_twos.txt'), raw_twos_code);
    write_vector(fullfile(vector_dir, 'g_pipeline_fft_expected.txt'), fft_expected);
    fprintf('Generated %d raw ADC codes and %d end-to-end FFT inputs.\n', ...
        raw_count, frame_length);
end

function output = fixed_fir(input, coeff, fraction_bits)
    output = zeros(numel(input), 1);
    input_i64 = int64(input(:));
    coeff_i64 = int64(coeff(:));
    for n = 1:numel(input)
        first_sample = max(1, n-numel(coeff)+1);
        sample_slice = input_i64(n:-1:first_sample);
        accumulator = sum(sample_slice.*coeff_i64(1:numel(sample_slice)));
        output(n) = floor((double(accumulator)+2^(fraction_bits-1))/2^fraction_bits);
    end
end

function write_vector(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end
