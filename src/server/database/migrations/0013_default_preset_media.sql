UPDATE `obfuscator_presets_table`
SET `masking` = 'MEDIA', `dummy` = 40, `verbose` = 'error'
WHERE `is_default` = 1
  AND `masking` = 'STUN'
  AND `dummy` = 10
  AND `verbose` = 'info';
