<?php
// Reference tokenizer audit only. Generated source strings are tokenized, not executed.
$rows = [];
foreach (['start', 'continue'] as $position) {
    for ($byte = 0; $byte < 256; $byte++) {
        $name = $position === 'start' ? chr($byte) . 'z' . $byte : 'z' . chr($byte) . 'z' . $byte;
        $source = '<?php function ' . $name . '() {}';
        $accepted = false;
        $token = null;
        $error = null;
        try {
            $afterFunction = false;
            foreach (token_get_all($source) as $entry) {
                if (is_array($entry) && $entry[0] === T_FUNCTION) {
                    $afterFunction = true;
                    continue;
                }
                if (!$afterFunction || (is_array($entry) && $entry[0] === T_WHITESPACE)) {
                    continue;
                }
                if (is_array($entry)) {
                    $token = ['type' => token_name($entry[0]), 'bytes_base64' => base64_encode($entry[1])];
                    $accepted = $entry[0] === T_STRING && $entry[1] === $name;
                } else {
                    $token = ['type' => 'single_byte', 'bytes_base64' => base64_encode($entry)];
                }
                break;
            }
        } catch (Throwable $failure) {
            $error = ['class' => get_class($failure), 'message_base64' => base64_encode($failure->getMessage())];
        }
        $rows[] = [
            'position' => $position,
            'byte' => $byte,
            'name_base64' => base64_encode($name),
            'source_base64' => base64_encode($source),
            'whole_name_is_T_STRING' => $accepted,
            'first_name_token' => $token,
            'lexer_error' => $error,
        ];
    }
}
echo json_encode(['scope' => 'All256 byte values in each identifier byte position; tokenizer only, not all parser contexts', 'rows' => $rows], JSON_THROW_ON_ERROR);
