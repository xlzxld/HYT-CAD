jrt_param : dialog {
  label = "加热条参数设置";
  : text { key = "tpl_name"; label = "当前模板"; width = 40; }
  : boxed_column {
    label = "加热条参数";
    : row {
      : edit_box { key = "jrt_offset"; label = "流道线偏移距离:"; edit_width = 10; }
      : edit_box { key = "jrt_cap_inset"; label = "封闭线内偏移距离:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "jrt_fillet_r"; label = "圆角半径R:"; edit_width = 10; }
      : edit_box { key = "jrt_cap_r"; label = "封闭线圆角半径R:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "jrt_inner_step"; label = "向内偏移步长:"; edit_width = 10; }
      : edit_box { key = "jrt_inner_count"; label = "内向偏移次数:"; edit_width = 10; }
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
    : radio_button { key = "tpl1"; label = "通用二 — JRT单壁线自动补边成闭合轮廓→朝JRTDW内嵌套(步长*次数)+出线口; 多段源线按手画轮廓处理"; }
  }
  : row {
    spacer; ok_button; cancel_button;
  }
}
