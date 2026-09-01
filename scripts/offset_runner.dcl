dt_param : dialog {
  label = "分流板参数设置";
  : text { key = "tpl_name"; label = "当前模板"; width = 40; }
  : boxed_column {
    label = "分流板参数";
    : row {
      : edit_box { key = "offset_dist"; label = "分流板偏移距离:"; edit_width = 10; }
      : edit_box { key = "hole_dist"; label = "假体偏移距离:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "hole_extend"; label = "假体端头延长:"; edit_width = 10; }
      : edit_box { key = "fillet_r"; label = "分流板圆角R:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "fillet_r_hole"; label = "假体圆角R:"; edit_width = 10; }
      : edit_box { key = "chamfer_d"; label = "封口倒角距离:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "screw_in"; label = "螺丝孔内偏:"; edit_width = 10; }
      : edit_box { key = "screw_r"; label = "螺丝孔R:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "nozzle_offset"; label = "热咀偏移:"; edit_width = 10; }
      : edit_box { key = "nozzle_r"; label = "热咀半径R:"; edit_width = 10; }
    }
    : row {
      : edit_box { key = "pin_r"; label = "点孔半径R:"; edit_width = 10; }
    }
  }
  : toggle { key = "jt_envelope"; label = "假体用包络法(FLB外扩整体圆角矩形)"; }
  : row {
    : button { key = "reset"; label = "恢复默认"; width = 10; }
    spacer;
    ok_button;
    cancel_button;
  }
}

off_template_select : dialog {
  label = "选择分流板模板";
  : boxed_radio_column {
    label = "模板";
    : radio_button { key = "otpl0"; label = "通用 — 现状全流程: 偏移+裁剪+断口圆角+封口+螺丝+倒角+假体+热咀"; }
    : radio_button { key = "otpl1"; label = "矩形 — LD范围向外扩矩形板边(四角倒角)+圆角矩形假体; 热咀拐点/预画RZ, 螺丝板边中点/预画LS"; }
  }
  : row {
    spacer; ok_button; cancel_button;
  }
}
