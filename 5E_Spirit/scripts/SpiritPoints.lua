-- CurrentHP Launch Message

COLOR_HEALTH_UNWOUNDED = "0070C0";
COLOR_HEALTH_DYING_OR_DEAD = "C0C0C0";

COLOR_HEALTH_SIMPLE_WOUNDED = "00B3C0";
COLOR_HEALTH_SIMPLE_BLOODIED = "00C044";

COLOR_HEALTH_LT_WOUNDS = "00B3C0";
COLOR_HEALTH_MOD_WOUNDS = "00C0C0";
COLOR_HEALTH_HVY_WOUNDS = "00C08A";
COLOR_HEALTH_CRIT_WOUNDS = "00C044";

function onInit()
	-- Create launch message
	local msg = {sender = "", font = "emotefont", icon="spIcon"};
	msg.text = "Spirit Points.\rWritten by CanadaBry.\rCopyright 2021 Smiteworks USA, LLC."
	-- Send launch message
	ChatManager.registerLaunchMessage(msg);

	wrapApplyDamage();
	wrapOnSystemShockResultRoll();
	wrapAddNPC();
	wrapGetHealthStatus();
	-- wrapGetTokenHealthInfo();
	wrapGetHealthInfo();

end	

function wrapApplyDamage()
	ActionDamage.applyDamage = applyDamage;
end

function wrapOnSystemShockResultRoll()
	ActionsManager.registerResultHandler("systemshockresult", onSystemShockResultRoll);
end

function wrapAddNPC()
	CombatManager.setCustomAddNPC(addNPC);
end

function wrapGetHealthStatus()
	ActorHealthManager.getHealthStatus = getHealthStatus;
end

function wrapGetTokenHealthInfo()
	ActorHealthManager.getTokenHealthInfo = getTokenHealthInfo;
end

function wrapGetHealthInfo()
	ActorHealthManager.getHealthInfo = getHealthInfo;
end

function applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
	-- Get health fields
	local nTotalHP, nTempHP, nWounds, nDeathSaveSuccess, nDeathSaveFail, nTotalSP, nWoundsSP;

	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if not nodeTarget then
		return;
	end
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, "hp.total", 0);
		nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0);
		nWounds = DB.getValue(nodeTarget, "hp.wounds", 0);
		nDeathSaveSuccess = DB.getValue(nodeTarget, "hp.deathsavesuccess", 0);
		nDeathSaveFail = DB.getValue(nodeTarget, "hp.deathsavefail", 0);
		nTotalSP = DB.getValue(nodeTarget, "sp.total", 0);
		nWoundsSP = DB.getValue(nodeTarget, "sp.wounds", 0);
	elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0);
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0);
		nWounds = DB.getValue(nodeTarget, "wounds", 0);
		nDeathSaveSuccess = DB.getValue(nodeTarget, "deathsavesuccess", 0);
		nDeathSaveFail = DB.getValue(nodeTarget, "deathsavefail", 0);
		nTotalSP = DB.getValue(nodeTarget, "sptotal", 0);
		nWoundsSP = DB.getValue(nodeTarget, "spwnd", 0);
	else
		return;
	end

	-- Prepare for notifications
	local aNotifications = {};
	local nConcentrationDamage = 0;
	local bRemoveTarget = false;

	-- Remember current health status
	local sOriginalStatus = ActorHealthManager.getHealthStatus(rTarget);

	-- Decode damage/heal description
	local rDamageOutput = ActionDamage.decodeDamageText(nTotal, sDamage);
	
	-- Healing
	if rDamageOutput.sType == "recovery" then
		local sClassNode = string.match(sDamage, "%[NODE:([^]]+)%]");
		
		-- [[ Added check for SP Wound here]] --
		if (nWounds <= 0) and (nWoundsSP <= 0) then
			table.insert(aNotifications, "[NOT WOUNDED]");
		else
			-- Determine whether HD available
			local nClassHD = 0;
			local nClassHDMult = 0;
			local nClassHDUsed = 0;
			if (sTargetNodeType == "pc") and sClassNode then
				local nodeClass = DB.findNode(sClassNode);
				if nodeClass then
					nClassHD = DB.getValue(nodeClass, "level", 0);
					nClassHDMult = #(DB.getValue(nodeClass, "hddie", {}));
					nClassHDUsed = DB.getValue(nodeClass, "hdused", 0);
				end
			end
			
			if (nClassHD * nClassHDMult) <= nClassHDUsed then
				table.insert(aNotifications, "[INSUFFICIENT HIT DICE FOR THIS CLASS]");
			else
				-- Calculate heal amounts
				local nHealAmount = rDamageOutput.nVal;
				
				-- If healing from zero (or negative), then remove Stable effect and reset wounds to match HP
				if (nHealAmount > 0) and (nWounds >= nTotalHP) then
					EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Stable");
					nWounds = nTotalHP;
				end

				-- [[ IF RESTORING SPIRIT FROM BELOW 0 ]] --
				if (nHealAmount > 0) and (nWoundsSP >= nTotalSP) and (nTotalSP ~= 0) then
					nWoundsSP = nTotalSP;
				end
				
				-- [[ HEAL SPIRIT POINTS ]] --
				local nWoundHealAmount;
				if (nWoundsSP > 0) and (nTotalSP ~= 0) then
					nWoundHealAmount = math.min(nHealAmount, nWoundsSP);
					nWoundsSP = nWoundsSP - nWoundHealAmount;
					table.insert(aNotifications, "[SPIRIT]");
				else
					nWoundHealAmount = math.min(nHealAmount, nWounds);
					nWounds = nWounds - nWoundHealAmount;
					table.insert(aNotifications, "[HEALTH]");
				end
				
				-- Display actual heal amount
				rDamageOutput.nVal = nWoundHealAmount;
				rDamageOutput.sVal = string.format("%01d", nWoundHealAmount);
				
				-- Decrement HD used
				if (sTargetNodeType == "pc") and sClassNode then
					local nodeClass = DB.findNode(sClassNode);
					if nodeClass then
						DB.setValue(nodeClass, "hdused", "number", nClassHDUsed + 1);
						rDamageOutput.sVal = rDamageOutput.sVal .. "][HD-1";
					end
				end
			end
		end

	-- Healing
	elseif rDamageOutput.sType == "heal" then
		-- [[ Added check for SP Wound here]] --
		if (nWounds <= 0) and (nWoundsSP <= 0) then
			table.insert(aNotifications, "[NOT WOUNDED]");
		else
			-- Calculate heal amounts
			local nHealAmount = rDamageOutput.nVal;
			
			-- If healing from zero (or negative), then remove Stable effect and reset wounds to match HP
			if (nHealAmount > 0) and (nWounds >= nTotalHP) then
				EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Stable");
				nWounds = nTotalHP;
			end
			
			-- [[ IF RESTORING SPIRIT FROM BELOW 0 ]] --
			if (nHealAmount > 0) and (nWoundsSP >= nTotalSP) and (nTotalSP ~= 0) then
				nWoundsSP = nTotalSP;
			end
			
			-- [[ HEAL SPIRIT POINTS ]] --
			local nWoundHealAmount;
			if (nWoundsSP > 0)  and (nTotalSP ~= 0) then
				nWoundHealAmount = math.min(nHealAmount, nWoundsSP);
				nWoundsSP = nWoundsSP - nWoundHealAmount;
				table.insert(aNotifications, "[SPIRIT]");
			else
				nWoundHealAmount = math.min(nHealAmount, nWounds);
				nWounds = nWounds - nWoundHealAmount;
				table.insert(aNotifications, "[HEALTH]");
			end
			
			-- Display actual heal amount
			rDamageOutput.nVal = nWoundHealAmount;
			rDamageOutput.sVal = string.format("%01d", nWoundHealAmount);
		end

	-- Temporary hit points
	elseif rDamageOutput.sType == "temphp" then
		nTempHP = math.max(nTempHP, nTotal);

	-- Damage
	else
		-- Apply any targeted damage effects 
		-- NOTE: Dice determined randomly, instead of rolled
		if rSource and rTarget and rTarget.nOrder then
			local bCritical = string.match(sDamage, "%[CRITICAL%]");
			local aTargetedDamage = EffectManager5E.getEffectsBonusByType(rSource, {"DMG"}, true, rDamageOutput.aDamageFilter, rTarget, true);

			local nDamageEffectTotal = 0;
			local nDamageEffectCount = 0;
			for k, v in pairs(aTargetedDamage) do
				local bValid = true;
				local aSplitByDmgType = StringManager.split(k, ",", true);
				for _,vDmgType in ipairs(aSplitByDmgType) do
					if vDmgType == "critical" and not bCritical then
						bValid = false;
					end
				end
				
				if bValid then
					local nSubTotal = StringManager.evalDice(v.dice, v.mod);
					
					local sDamageType = rDamageOutput.sFirstDamageType;
					if sDamageType then
						sDamageType = sDamageType .. "," .. k;
					else
						sDamageType = k;
					end

					rDamageOutput.aDamageTypes[sDamageType] = (rDamageOutput.aDamageTypes[sDamageType] or 0) + nSubTotal;
					
					nDamageEffectTotal = nDamageEffectTotal + nSubTotal;
					nDamageEffectCount = nDamageEffectCount + 1;
				end
			end
			nTotal = nTotal + nDamageEffectTotal;

			if nDamageEffectCount > 0 then
				if nDamageEffectTotal ~= 0 then
					local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]";
					table.insert(aNotifications, string.format(sFormat, nDamageEffectTotal));
				else
					table.insert(aNotifications, "[" .. Interface.getString("effects_tag") .. "]");
				end
			end
		end
		
		-- Handle avoidance/evasion and half damage
		local isAvoided = false;
		local isHalf = string.match(sDamage, "%[HALF%]");
		local sAttack = string.match(sDamage, "%[DAMAGE[^]]*%] ([^[]+)");
		if sAttack then
			local sDamageState = ActionDamage.getDamageState(rSource, rTarget, StringManager.trim(sAttack));
			if sDamageState == "none" then
				isAvoided = true;
				bRemoveTarget = true;
			elseif sDamageState == "half_success" then
				isHalf = true;
				bRemoveTarget = true;
			elseif sDamageState == "half_failure" then
				isHalf = true;
			end
		end
		if isAvoided then
			table.insert(aNotifications, "[EVADED]");
			for kType, nType in pairs(rDamageOutput.aDamageTypes) do
				rDamageOutput.aDamageTypes[kType] = 0;
			end
			nTotal = 0;
		elseif isHalf then
			table.insert(aNotifications, "[HALF]");
			local bCarry = false;
			for kType, nType in pairs(rDamageOutput.aDamageTypes) do
				local nOddCheck = nType % 2;
				rDamageOutput.aDamageTypes[kType] = math.floor(nType / 2);
				if nOddCheck == 1 then
					if bCarry then
						rDamageOutput.aDamageTypes[kType] = rDamageOutput.aDamageTypes[kType] + 1;
						bCarry = false;
					else
						bCarry = true;
					end
				end
			end
			nTotal = math.max(math.floor(nTotal / 2), 1);
		end
		
		-- Apply damage type adjustments
		local nDamageAdjust, bVulnerable, bResist = ActionDamage.getDamageAdjust(rSource, rTarget, nTotal, rDamageOutput);
		local nAdjustedDamage = nTotal + nDamageAdjust;
		if nAdjustedDamage < 0 then
			nAdjustedDamage = 0;
		end
		if bResist then
			if nAdjustedDamage <= 0 then
				table.insert(aNotifications, "[RESISTED]");
			else
				table.insert(aNotifications, "[PARTIALLY RESISTED]");
			end
		end
		if bVulnerable then
			table.insert(aNotifications, "[VULNERABLE]");
		end
		
		-- Prepare for concentration checks if damaged
		nConcentrationDamage = nAdjustedDamage;
		
		-- Reduce damage by temporary hit points
		if nTempHP > 0 and nAdjustedDamage > 0 then
			if nAdjustedDamage > nTempHP then
				nAdjustedDamage = nAdjustedDamage - nTempHP;
				nTempHP = 0;
				table.insert(aNotifications, "[PARTIALLY ABSORBED]");
			else
				nTempHP = nTempHP - nAdjustedDamage;
				nAdjustedDamage = 0;
				table.insert(aNotifications, "[ABSORBED]");
			end
		end

		-- Apply remaining damage
		if nAdjustedDamage > 0 then
			-- Remember previous wounds
			local nPrevWounds = nWounds;
			
			-- Apply wounds
			-- [[ Apply wounds ]] --
			if nTotalSP > nWoundsSP then
				nWoundsSP = math.max(nWoundsSP + nAdjustedDamage, 0);
				if nWoundsSP > nTotalSP then
					local nBleedOver = nWoundsSP - nTotalSP;
					nWoundsSP = nTotalSP;
					local hpDamage =  math.floor(nBleedOver / 2);
					EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "DISPIRITED", nDuration = 0 }, true);
					if hpDamage > 0 then
						table.insert(aNotifications, "[DAMAGE EXCEEDS SPIRIT POINTS BY " .. hpDamage.. "]");
						nAdjustedDamage = nAdjustedDamage - nBleedOver + hpDamage;
						nWounds = math.max(nWounds + hpDamage, 0);
					end
					table.insert(aNotifications, "[DISPIRITED]");
				end
				if OptionsManager.isOption("HRMD", "on") and (nAdjustedDamage >= (nTotalSP / 2)) then
					ActionSave.performSystemShockRoll(nil, rTarget);
				end
			else
				nWounds = math.max(nWounds + nAdjustedDamage, 0);
			end

			-- Calculate wounds above HP
			local nRemainder = 0;
			if nWounds > nTotalHP then
				nRemainder = nWounds - nTotalHP;
				nWounds = nTotalHP;
			end
			
			-- Deal with remainder damage
			if nRemainder >= nTotalHP then
				table.insert(aNotifications, "[INSTANT DEATH]");
				nDeathSaveFail = 3;
			elseif nRemainder > 0 then
				table.insert(aNotifications, "[DAMAGE EXCEEDS HIT POINTS BY " .. nRemainder.. "]");
				if nPrevWounds >= nTotalHP then
					if rDamageOutput.bCritical then
						nDeathSaveFail = nDeathSaveFail + 2;
					else
						nDeathSaveFail = nDeathSaveFail + 1;
					end
				end
			else
				if OptionsManager.isOption("HRMD", "on") and (nAdjustedDamage >= (nTotalHP / 2)) and sTargetNodeType ~= "pc" and nTotalSP ~= 0 then
					ActionSave.performSystemShockRoll(nil, rTarget);
				end
			end
			
			local nodeTargetCT = ActorManager.getCTNode(rTarget);
			if nodeTargetCT then
				-- Handle stable situation
				EffectManager.removeEffect(nodeTargetCT, "Stable");

				-- Disable regeneration next round on correct damage type
				-- Calculate which damage types actually did damage
				local aTempDamageTypes = {};
				local aActualDamageTypes = {};
				for k,v in pairs(rDamageOutput.aDamageTypes) do
					if v > 0 then
						table.insert(aTempDamageTypes, k);
					end
				end
				local aActualDamageTypes = StringManager.split(table.concat(aTempDamageTypes, ","), ",", true);
				
				-- Check target's effects for regeneration effects that match
				for _,v in pairs(DB.getChildren(nodeTargetCT, "effects")) do
					local nActive = DB.getValue(v, "isactive", 0);
					if (nActive == 1) then
						local bMatch = false;
						local sLabel = DB.getValue(v, "label", "");
						local aEffectComps = EffectManager.parseEffect(sLabel);
						for i = 1, #aEffectComps do
							local rEffectComp = EffectManager5E.parseEffectComp(aEffectComps[i]);
							if rEffectComp.type == "REGEN" then
								for _,v2 in pairs(rEffectComp.remainder) do
									if StringManager.contains(aActualDamageTypes, v2) then
										bMatch = true;
									end
								end
							end
							
							if bMatch then
								EffectManager.disableEffect(nodeTargetCT, v);
							end
						end
					end
				end
			end
		end
		
		-- Update the damage output variable to reflect adjustments
		rDamageOutput.nVal = nAdjustedDamage;
		rDamageOutput.sVal = string.format("%01d", nAdjustedDamage);
	end
	
	-- Clear death saves if health greater than zero
	if nWounds < nTotalHP then
		nDeathSaveSuccess = 0;
		nDeathSaveFail = 0;
		if EffectManager5E.hasEffect(rTarget, "Stable") then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Stable");
		end
		if EffectManager5E.hasEffect(rTarget, "Unconscious") then
			EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "Unconscious");
		end
	else
		if not EffectManager5E.hasEffect(rTarget, "Unconscious") then
			EffectManager.addEffect("", "", ActorManager.getCTNode(rTarget), { sName = "Unconscious", nDuration = 0 }, true);
		end
	end

	if nWoundsSP < nTotalSP then
		EffectManager.removeEffect(ActorManager.getCTNode(rTarget), "DISPIRITED");
	end

	-- Set health fields
	if sTargetNodeType == "pc" then
		DB.setValue(nodeTarget, "hp.deathsavesuccess", "number", math.min(nDeathSaveSuccess, 3));
		DB.setValue(nodeTarget, "hp.deathsavefail", "number", math.min(nDeathSaveFail, 3));
		DB.setValue(nodeTarget, "hp.temporary", "number", nTempHP);
		DB.setValue(nodeTarget, "hp.wounds", "number", nWounds);
		DB.setValue(nodeTarget, "sp.total", "number", nTotalSP);
		DB.setValue(nodeTarget, "sp.wounds", "number", nWoundsSP);
	else
		DB.setValue(nodeTarget, "deathsavesuccess", "number", math.min(nDeathSaveSuccess, 3));
		DB.setValue(nodeTarget, "deathsavefail", "number", math.min(nDeathSaveFail, 3));
		DB.setValue(nodeTarget, "hptemp", "number", nTempHP);
		DB.setValue(nodeTarget, "wounds", "number", nWounds);
		DB.setValue(nodeTarget, "spwnd", "number", nWoundsSP);
	end

	-- Check for status change
	local bShowStatus = false;
	if ActorManager.getFaction(rTarget) == "friend" then
		bShowStatus = not OptionsManager.isOption("SHPC", "off");
	else
		bShowStatus = not OptionsManager.isOption("SHNPC", "off");
	end
	if bShowStatus then
		local sNewStatus = ActorHealthManager.getHealthStatus(rTarget);
		if sOriginalStatus ~= sNewStatus then
			table.insert(aNotifications, "[" .. Interface.getString("combat_tag_status") .. ": " .. sNewStatus .. "]");
		end
	end
	
	-- Output results
	ActionDamage.messageDamage(rSource, rTarget, bSecret, rDamageOutput.sTypeOutput, sDamage, rDamageOutput.sVal, table.concat(aNotifications, " "));

	-- Remove target after applying damage
	if bRemoveTarget and rSource and rTarget then
		TargetingManager.removeTarget(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rTarget));
	end

	-- Check for required concentration checks
	if nConcentrationDamage > 0 and ActionSave.hasConcentrationEffects(rTarget) then
		if nWounds < nTotalHP then
			local nTargetDC = math.max(math.floor(nConcentrationDamage / 2), 10);
			ActionSave.performConcentrationRoll(nil, rTarget, nTargetDC);
		else
			ActionSave.expireConcentrationEffects(rTarget);
		end
	end
end

function onSystemShockResultRoll(rSource, rTarget, rRoll)
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);

	local sNodeType, nodeActor = ActorManager.getTypeAndNode(rSource);
	if not nodeActor then
		return;
	end
	local nodeCT = ActorManager.getCTNode(rSource)
	local nTotal = ActionsManager.total(rRoll);
	
	-- [[ PCs take damage to spirit ]] -- 
	if (nTotal <= 1) then
		if sNodeType == "pc" then
			DB.setValue(nodeActor, "sp.wounds", "number", DB.getValue(nodeActor, "sp.total", 0));
			rMessage.text = rMessage.text .. " -> [SPIRIT DROPPED TO ZERO]";
		else
			DB.setValue(nodeActor, "wounds", "number", DB.getValue(nodeActor, "hptotal", 0));
			if not EffectManager5E.hasEffect(rSource, "Unconscious") then
				EffectManager.addEffect("", "", nodeCT, { sName = "Unconscious", nDuration = 0 }, true);
			end
			EffectManager.removeEffect(nodeCT, "Stable");
			rMessage.text = rMessage.text .. " -> [DROPPED TO ZERO]";
		end
		
	elseif ((nTotal == 2) or (nTotal == 3)) then
		if sNodeType == "pc" then
			DB.setValue(nodeActor, "sp.wounds", "number", DB.getValue(nodeActor, "sp.total", 0));
			rMessage.text = rMessage.text .. " -> [SPIRIT DROPPED TO ZERO]";
		else
			DB.setValue(nodeActor, "wounds", "number", DB.getValue(nodeActor, "hptotal", 0));
			if not EffectManager5E.hasEffect(rSource, "Unconscious") then
				EffectManager.addEffect("", "", nodeCT, { sName = "Unconscious", nDuration = 0 }, true);
			end
			if not EffectManager5E.hasEffect(rSource, "Stable") then
				local aEffect = { sName = "Stable", nDuration = 0 };
				if ActorManager.getFaction(rSource) ~= "friend" then
					aEffect.nGMOnly = 1;
				end
				EffectManager.addEffect("", "", nodeCT, aEffect, true);
			end
			rMessage.text = rMessage.text .. " -> [DROPPED TO ZERO, BUT STABLE]";
		end
		
	elseif ((nTotal == 4) or (nTotal == 5)) then
		local aEffect = { sName = "System shock; Stunned", nDuration = 1 };
		if ActorManager.getFaction(rSource) ~= "friend" then
			aEffect.nGMOnly = 1;
		end
		EffectManager.addEffect("", "", nodeCT, aEffect, true);
		rMessage.text = rMessage.text .. " -> [STUNNED]";
		
	elseif ((nTotal == 6) or (nTotal == 7)) then
		local aEffect = { sName = "System shock; NOTE: No reactions; DISATK; DISCHK", nDuration = 1 };
		if ActorManager.getFaction(rSource) ~= "friend" then
			aEffect.nGMOnly = 1;
		end
		EffectManager.addEffect("", "", nodeCT, aEffect, true);
		rMessage.text = rMessage.text .. " -> [NO REACTIONS, AND DISADVANTAGE]";
		
	else -- if (nTotal >= 8) then
		local aEffect = { sName = "System shock; NOTE: No reactions", nDuration = 1 };
		if ActorManager.getFaction(rSource) ~= "friend" then
			aEffect.nGMOnly = 1;
		end
		EffectManager.addEffect("", "", nodeCT, aEffect, true);
		rMessage.text = rMessage.text .. " -> [NO REACTIONS]";
	end
	
	Comm.deliverChatMessage(rMessage);
end

function getSpiritColor(v)
	local nPercentWounded,_ = getDamagePercent(v);
	local sColor = getTieredSpiritColor(nPercentWounded);
	return sColor;
end

function getDamagePercent(v)
	local rActor = ActorManager.resolveActor(v);
	local nSP = 0;
	local nDamageSP = 0;
	local nHP = 0;
	local nDamage = 0;

	local nodeCT = ActorManager.getCTNode(rActor);
	if nodeCT then
		nSP = math.max(DB.getValue(nodeCT, "sptotal", 0), 0);
		nDamageSP = math.max(DB.getValue(nodeCT, "spwnd", 0), 0);
		nHP = math.max(DB.getValue(nodeCT, "hptotal", 0), 0);
		nDamage = math.max(DB.getValue(nodeCT, "wounds", 0), 0);
	elseif ActorManager.isPC(rActor) then
		local nodePC = ActorManager.getCreatureNode(rActor);
		if nodePC then
			nSP = math.max(DB.getValue(nodePC, "sp.total", 0), 0);
			nDamageSP = math.max(DB.getValue(nodePC, "sp.wounds", 0), 0);
			nHP = math.max(DB.getValue(nodePC, "hp.total", 0), 0);
			nDamage = math.max(DB.getValue(nodePC, "hp.wounds", 0), 0);
		end
	end
	
	local nPercentWounded = 1;
	if nSP > 0 then
		nPercentWounded = nDamageSP / nSP;
	end
	
	local sStatus;
	if nPercentWounded < 1 and nDamage < nHP then
		sStatus = ActorHealthManager.getDefaultStatusFromWoundPercent(nPercentWounded);
	else
		_, sStatus = ActorHealthManager.getWoundPercent(v);
		sStatus = "DS | " .. sStatus;
	end
	
	return nPercentWounded, sStatus;
end

function getHealthStatus(v)
	local rActor = ActorManager.resolveActor(v);
	local nSP = 0;

	local nodeCT = ActorManager.getCTNode(rActor);
	if nodeCT then
		nSP = math.max(DB.getValue(nodeCT, "sptotal", 0), 0);
	elseif ActorManager.isPC(rActor) then
		local nodePC = ActorManager.getCreatureNode(rActor);
		if nodePC then
			nSP = math.max(DB.getValue(nodePC, "sp.total", 0), 0);
		end
	end

	local sStatus;
	if nSP > 0 then
		_,sStatus = getDamagePercent(v);
	else
		_,sStatus = ActorHealthManager.getWoundPercent(v);
	end

	return sStatus;
end

function getHealthInfo(v)
	local rActor = ActorManager.resolveActor(v);
	local nSP = 0;
	local nWounds = 0;
	local nHP = 0;

	local nodeCT = ActorManager.getCTNode(rActor);
	if nodeCT then
		nSP = math.max(DB.getValue(nodeCT, "sptotal", 0), 0);
		nWounds = math.max(DB.getValue(nodeCT, "wounds", 0), 0);
		nHP = math.max(DB.getValue(nodeCT, "hptotal", 0), 0);

	elseif ActorManager.isPC(rActor) then
		local nodePC = ActorManager.getCreatureNode(rActor);
		if nodePC then
			nSP = math.max(DB.getValue(nodePC, "sp.total", 0), 0);
			nWounds = math.max(DB.getValue(nodePC, "hp.wounds", 0), 0);
			nHP = math.max(DB.getValue(nodePC, "hp.total", 0), 0);
		end
	end

	local nPercentWounded,sStatus,sColor;
	if nSP > 0 then
		nPercentWounded,sStatus = getDamagePercent(v);
		if nPercentWounded < 1 and nWounds < 1 then
			sColor = getTieredSpiritColor(nPercentWounded);
		else
			nPercentWounded,_ = ActorHealthManager.getWoundPercent(v);
			sColor = ColorManager.getHealthColor(nPercentWounded, true);
		end
	else
		nPercentWounded,sStatus = ActorHealthManager.getWoundPercent(v);
		sColor = ColorManager.getHealthColor(nPercentWounded, true);
	end

	return nPercentWounded,sStatus,sColor;
end

function getStatusColor(v)
	local rActor = ActorManager.resolveActor(v);
	local nSP = 0;
	local nHP = 0;
	local nDamage = 0;

	local nodeCT = ActorManager.getCTNode(rActor);
	if nodeCT then
		nSP = math.max(DB.getValue(nodeCT, "sptotal", 0), 0);
		nHP = math.max(DB.getValue(nodeCT, "hptotal", 0), 0);
		nDamage = math.max(DB.getValue(nodeCT, "wounds", 0), 0);
	elseif ActorManager.isPC(rActor) then
		local nodePC = ActorManager.getCreatureNode(rActor);
		if nodePC then
			nSP = math.max(DB.getValue(nodePC, "sp.total", 0), 0);
			nHP = math.max(DB.getValue(nodePC, "hp.total", 0), 0);
			nDamage = math.max(DB.getValue(nodePC, "hp.wounds", 0), 0);
		end
	end

	local nPercentWounded,sColor;
	if nSP > 0 then
		nPercentWounded,_ = getDamagePercent(v);
		if nPercentWounded < 1  and nHP > nDamage then
			sColor = getTieredSpiritColor(nPercentWounded);
		else
			nPercentWounded,_ = ActorHealthManager.getWoundPercent(v);
			sColor = ColorManager.getHealthColor(nPercentWounded, true);
		end
	else
		nPercentWounded,_ = ActorHealthManager.getWoundPercent(v);
		sColor = ColorManager.getHealthColor(nPercentWounded, true);
	end

	return sColor;
end

function getTieredSpiritColor(nPercentWounded)
	local sColor;
	if nPercentWounded >= 1 then
		sColor = COLOR_HEALTH_DYING_OR_DEAD;
	elseif nPercentWounded <= 0 then
		sColor = COLOR_HEALTH_UNWOUNDED;
	elseif OptionsManager.isOption("WNDC", "detailed") then
		if nPercentWounded >= 0.75 then
			sColor = COLOR_HEALTH_CRIT_WOUNDS;
		elseif nPercentWounded >= 0.5 then
			sColor = COLOR_HEALTH_HVY_WOUNDS;
		elseif nPercentWounded >= 0.25 then
			sColor = COLOR_HEALTH_MOD_WOUNDS;
		else
			sColor = COLOR_HEALTH_LT_WOUNDS;
		end
	else
		if nPercentWounded >= 0.5 then
			sColor = COLOR_HEALTH_SIMPLE_BLOODIED;
		else
			sColor = COLOR_HEALTH_SIMPLE_WOUNDED;
		end
	end
	return sColor;
end

function addNPC(sClass, nodeNPC, sName)
	local nodeEntry = CombatManager2.addNPC(sClass, nodeNPC, sName);
	local nSP = DB.getValue(nodeNPC, "sp", 0);
	DB.setValue(nodeEntry, "sptotal", "number", nSP);

	return nodeEntry
end