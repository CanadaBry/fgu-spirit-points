function onInit()
    super.onInit();

    onLinkChanged();
    onSpiritChanged();

end

function onSpiritChanged()
	local rActor = ActorManager.resolveActor(getDatabaseNode())
	local sColor = SpiritPoints.getSpiritColor(rActor);
	local sStatus = SpiritPoints.getHealthStatus(getDatabaseNode());

	spwnd.setColor(sColor);
    status.setValue(sStatus);
end

function onLinkChanged()
    local sClass,_ = link.getValue();
	if sClass == "charsheet" then
		linkSpiritFields();
	end
	super.onLinkChanged();
end

function linkSpiritFields()
    local nodeChar = link.getTargetDatabaseNode();
	if nodeChar then
        sptotal.setLink(nodeChar.createChild("sp.total", "number"));
        spwnd.setLink(nodeChar.createChild("sp.wounds", "number"));
    end
end