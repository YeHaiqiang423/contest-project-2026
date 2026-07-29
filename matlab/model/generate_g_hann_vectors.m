function generate_g_hann_vectors()
%GENERATE_G_HANN_VECTORS Production Hann ROM and bit-true small-frame vectors.

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir'), mkdir(vector_dir); end

    production_length = 4096;
    production_q15 = quantized_hann(production_length);
    write_hex(fullfile(vector_dir, 'g_hann_q15_unique.hex'), ...
        production_q15(1:production_length/2));

    test_length = 16;
    test_q15 = quantized_hann(test_length);
    test_input = int32([-32768; -24000; -16000; -8000; -4000; -1; 0; 1; ...
        4000; 8000; 12000; 16000; 20000; 24000; 30000; 32767]);
    product = int64(test_input).*int64(test_q15);
    test_expected = floor((double(product)+2^14)/2^15);

    write_hex(fullfile(vector_dir, 'g_hann_test_q15_unique.hex'), ...
        test_q15(1:test_length/2));
    write_decimal(fullfile(vector_dir, 'g_hann_test_input.txt'), test_input);
    write_decimal(fullfile(vector_dir, 'g_hann_test_expected.txt'), test_expected);
    fprintf('Generated 4096-point Hann ROM and %d bit-true test values.\n', test_length);
end

function q15 = quantized_hann(length_value)
    n = (0:length_value-1).';
    window = 0.5-0.5*cos(2*pi*n/(length_value-1));
    q15 = int32(round(window*32767));
end

function write_hex(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%04X\n', values);
end

function write_decimal(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open %s.', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end
