function generate_adc_frontend_vectors()
%GENERATE_ADC_FRONTEND_VECTORS Shared vectors for ADS6149 front-end RTL.

    adc_width = 14;
    decimation = 10;
    cycle_count = 173;
    code_modulus = 2^adc_width;
    sign_mask = 2^(adc_width-1);

    rng(6149, 'twister');
    signed_value = randi([-sign_mask, sign_mask-1], cycle_count, 1);
    directed = [-sign_mask; -sign_mask+1; -4097; -1; 0; 1; 4095; sign_mask-1];
    signed_value(1:numel(directed)) = directed;
    adc_valid = mod((0:cycle_count-1).', 11) ~= 4 & ...
        mod((0:cycle_count-1).', 17) ~= 9;

    twos_code = mod(signed_value, code_modulus);
    offset_code = bitxor(uint16(twos_code), uint16(sign_mask));
    expected_valid = false(cycle_count, 1);
    expected_value = zeros(cycle_count, 1);
    valid_index = 0;
    for k = 1:cycle_count
        if adc_valid(k)
            if mod(valid_index, decimation) == 0
                expected_valid(k) = true;
                expected_value(k) = signed_value(k);
            end
            valid_index = valid_index+1;
        end
    end

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir')
        mkdir(vector_dir);
    end
    vector_path = fullfile(vector_dir, 'adc_sample_frontend_vectors.txt');
    file_id = fopen(vector_path, 'w');
    assert(file_id >= 0, 'Cannot open vector file: %s', vector_path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    vectors = [double(adc_valid), double(twos_code), double(offset_code), ...
        double(expected_valid), double(expected_value)];
    fprintf(file_id, '%d %d %d %d %d\n', vectors.');
    fprintf('Generated %d ADS6149 front-end cycles in %s\n', ...
        cycle_count, vector_path);
end
