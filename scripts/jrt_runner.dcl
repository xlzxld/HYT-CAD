jrt_param : dialog {
  label = "加热条参数设置";
  : text { key = "tpl_name"; label = "当前模板"; width = 40; }
  : boxed_column {
    label = "加热条参数";
    : row {
      : edit_box { key = "jrt_inner_step"; label = "向内偏移步长:"; edit_width = 10; }
      : edit_box { key = "jrt_inner_count"; label = "内向偏移次数:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "jrt2_neck_len"; label = "出线颈线长度:"; edit_width = 10; }
      : edit_box { key = "jrt2_neck_off"; label = "出线颈线偏移:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "jrt2_close_r"; label = "出线封口圆角R:"; edit_width = 10; }
      : edit_box { key = "jrt2_trim_r"; label = "出线相交圆角R:"; edit_width = 10; }
    }
  }
  : row {
    : button { key = "reset"; label = "恢复默认"; width = 10; }
    spacer;
    ok_button;
    cancel_button;
  }
}

jrt_template_select : dialog {
  label = "选择加热条模板";
  : boxed_radio_column {
    label = "模板";
    : radio_button { key = "tpl0"; label = "通用一 — 端帽按相邻通道内壁间距判定(RZ整圆帽/封闭线圆弧帽)"; }
    : radio_button { key = "tpl1"; label = "通用二 — JRT源线朝JRTDW内嵌套(步长*次数)+出线口, 两头各一线连最内最外成闭环"; }
  }
  : row {
    spacer; ok_button; cancel_button;
  }
}
