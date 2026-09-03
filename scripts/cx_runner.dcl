dt_cx_param : dialog {
  label = "出线槽参数设置";
  : boxed_column {
    label = "基本设置";
    : row {
      : edit_box { key = "cx_dist"; label = "出线槽偏移:"; edit_width = 10; }
      : edit_box { key = "cx_extend"; label = "出线槽延长:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "cx_fillet_r_small"; label = "出线槽小圆角R:"; edit_width = 10; }
      : edit_box { key = "cx_fillet_r_large"; label = "出线槽大圆角R:"; edit_width = 10; }
    }
  }
  : row {
    : button { key = "reset"; label = "恢复默认"; width = 10; }
    spacer;
    ok_button;
    cancel_button;
  }
}
