function generate_sat_gain_vectors()
%GENERATE_SAT_GAIN_VECTORS Generate deterministic RTL stimulus and golden output.
% The example computes y = saturate_int16(3 * x).

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    vector_dir = fullfile(project_root, 'matlab', 'vectors');
    if ~exist(vector_dir, 'dir')
        mkdir(vector_dir);
    end

    directed = int16([ ...
        -32768, -20000, -10923, -10922, -1, 0, 1, ...
         10922, 10923, 20000, 32767]);
    rng(2026, 'twister');
    random_values = int16(randi([-32768, 32767], 53, 1));
    stimulus = [directed(:); random_values(:)];

    wide_result = int32(stimulus) * int32(3);
    golden = int16(min(max(wide_result, int32(-32768)), int32(32767)));

    write_decimal_vector(fullfile(vector_dir, 'sat_gain_input.txt'), stimulus);
    write_decimal_vector(fullfile(vector_dir, 'sat_gain_expected.txt'), golden);

    fprintf('Generated %d vectors in %s\n', numel(stimulus), vector_dir);
    fprintf('Input range: %d to %d; output range: %d to %d\n', ...
        min(stimulus), max(stimulus), min(golden), max(golden));
end

function write_decimal_vector(path, values)
    file_id = fopen(path, 'w');
    assert(file_id >= 0, 'Cannot open vector file: %s', path);
    cleanup = onCleanup(@() fclose(file_id)); %#ok<NASGU>
    fprintf(file_id, '%d\n', values);
end

