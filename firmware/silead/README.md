# Touch firmware

`gsl3676-frame157.fw` is the Silead GSL3676 firmware for this frame's touch
panel ("Kingvina_FG1509_2_GSL3676_HuiY", the `gsl_name` in the stock device
tree). It was extracted from the stock Android kernel (`backup/frame157/kernel.img`):
the stock gslX680 driver keeps a table of 0x60-byte entries `{char name[64];
fw_data *fw; u32 fw_len; u32 *config; u32 config_len}`; the entry at image
offset 0x137aea8 points to 4686 `{u32 reg, u32 val}` records at 0xcb86a8.
That is the format mainline `silead.c` loads. Installed on the frame as
`/usr/lib/firmware/silead/gsl3676-frame157.fw`.
