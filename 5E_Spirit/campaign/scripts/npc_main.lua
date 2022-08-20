function update()
    super.update();
    local nodeRecord = getDatabaseNode();
	local bReadOnly = WindowManager.getReadOnlyState(nodeRecord);
	sp.setReadOnly(bReadOnly);
end