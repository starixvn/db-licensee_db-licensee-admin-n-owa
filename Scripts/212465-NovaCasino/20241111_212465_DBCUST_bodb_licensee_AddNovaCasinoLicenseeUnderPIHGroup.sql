/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20221017@Danny
	DB: DBCUST.bodb_licensee
	Description: Add Seal888 to Label table
*/

--INSERT INTO Labels(LicenseeID, LabelID, LabelName, AffectedDate, IsKPISummary)
--SELECT 18, -- PIH
--		1605, --LabelID
--		'NovaCasino', --LabelName
--		'2024-11-01', -- AffectedDate
--		0 


UPDATE Labels WITH(ROWLOCK, UPDLOCK) SET LabelID = 50550 
WHERE LabelID = 1605 AND LabelName ='NovaCasino'

