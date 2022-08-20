-- 
-- Please see the license.html file included with this distribution for 
-- attribution and copyright information.
--

function onInit()
	super.onInit();
	onSpiritChanged();
end

function onFactionChanged()
	super.onInit();
	updateSpiritDisplay();
end

function onHealthChanged()
	super.onHealthChanged();
	local v = getDatabaseNode();
	local sColor = SpiritPoints.getStatusColor(v);
	status.setColor(sColor);
end

function onSpiritChanged()
	local rActor = ActorManager.resolveActor(getDatabaseNode());
	local sColor = SpiritPoints.getSpiritColor(rActor);

	spwnd.setColor(sColor);
	if sColor == "C0C0C0" then
		sColor = "008000";
	end
	status.setColor(sColor);
end

function updateSpiritDisplay()
	local sOption;
	if friendfoe.getStringValue() == "friend" then
		sOption = OptionsManager.getOption("SHPC");
	else
		sOption = OptionsManager.getOption("SHNPC");
	end
	
	if sOption == "detailed" then
		sptotal.setVisible(true);
		spwnd.setVisible(true);
		hptotal.setVisible(true);
		hptemp.setVisible(true);
		wounds.setVisible(true);

		status.setVisible(false);
	elseif sOption == "status" then
		sptotal.setVisible(false);
		spwnd.setVisible(false);
		hptotal.setVisible(false);
		hptemp.setVisible(false);
		wounds.setVisible(false);

		status.setVisible(true);
	else
		sptotal.setVisible(false);
		spwnd.setVisible(false);
		hptotal.setVisible(false);
		hptemp.setVisible(false);
		wounds.setVisible(false);

		status.setVisible(false);
	end
end