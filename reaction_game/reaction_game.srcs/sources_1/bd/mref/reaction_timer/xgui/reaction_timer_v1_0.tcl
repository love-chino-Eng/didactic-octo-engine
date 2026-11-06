# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CLK_FREQ_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEBOUNCE_EN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEBOUNCE_MS" -parent ${Page_0}


}

proc update_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to update CLK_FREQ_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_FREQ_HZ { PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to validate CLK_FREQ_HZ
	return true
}

proc update_PARAM_VALUE.DEBOUNCE_EN { PARAM_VALUE.DEBOUNCE_EN } {
	# Procedure called to update DEBOUNCE_EN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEBOUNCE_EN { PARAM_VALUE.DEBOUNCE_EN } {
	# Procedure called to validate DEBOUNCE_EN
	return true
}

proc update_PARAM_VALUE.DEBOUNCE_MS { PARAM_VALUE.DEBOUNCE_MS } {
	# Procedure called to update DEBOUNCE_MS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEBOUNCE_MS { PARAM_VALUE.DEBOUNCE_MS } {
	# Procedure called to validate DEBOUNCE_MS
	return true
}


proc update_MODELPARAM_VALUE.CLK_FREQ_HZ { MODELPARAM_VALUE.CLK_FREQ_HZ PARAM_VALUE.CLK_FREQ_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_FREQ_HZ}] ${MODELPARAM_VALUE.CLK_FREQ_HZ}
}

proc update_MODELPARAM_VALUE.DEBOUNCE_MS { MODELPARAM_VALUE.DEBOUNCE_MS PARAM_VALUE.DEBOUNCE_MS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEBOUNCE_MS}] ${MODELPARAM_VALUE.DEBOUNCE_MS}
}

proc update_MODELPARAM_VALUE.DEBOUNCE_EN { MODELPARAM_VALUE.DEBOUNCE_EN PARAM_VALUE.DEBOUNCE_EN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEBOUNCE_EN}] ${MODELPARAM_VALUE.DEBOUNCE_EN}
}

