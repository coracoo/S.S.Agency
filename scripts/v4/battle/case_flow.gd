class_name CaseFlowV4
extends RefCounted
## 案件流程载体（D 期）：委托承印时登记当前案件 id，
## 舞台串联（stage next）与真相场景据此取对应配置。static 而非 autoload：仅三处使用。

static var case_id := "night_patrol"
