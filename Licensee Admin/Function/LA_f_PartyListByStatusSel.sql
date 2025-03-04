/*<info serverAlias="DBLIC-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION LA_f_PartyListByStatusSel 
(
	@PartyIDs			VARCHAR(MAX),
	@LicenseeStatusIds	VARCHAR(100)	
)
	
/*  
	Created: 20210912@Danny
	Task: Filter Party by OIC status
	DB: DBLIC.bodb_licensee
	
	Revisions:  
		- 20211209@Danny: Initialize function
		- 20250304@Danny: Use STRING_SPLIT built-in function instead [RedmineID: #217961]

	Param's Explanation:				
*/RETURNS TABLE 
AS
RETURN 
(
	WITH statusList AS
	(
		SELECT CAST (value AS INT) StatusId FROM STRING_SPLIT(@LicenseeStatusIds,',')
	),
	oic_lic AS
	(
		SELECT RegisteredLicenseeName, LicenseeStatusId  FROM  DBOIC.bodb_OIC.dbo.licensee oic WITH (NOLOCK)
	),

	PartyList AS 
	(
		SELECT		op.PartyID,  CASE	WHEN la.IsDeposit = 0 THEN 3 -- Active (Credit)
										WHEN la.IsDeposit = 1 AND oic.LicenseeStatusId IS NULL THEN 999 -- 999: Unrecognized dummy status
										ELSE oic.LicenseeStatusId END  AS StatusID
		FROM		bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) 
		INNER JOIN	bodb_licensee.dbo.Licensees la WITH (NOLOCK) ON la.LicenseeId = op.OldRefID
		LEFT JOIN	oic_lic oic WITH (NOLOCK) ON oic.RegisteredLicenseeName = la.LicenseeName	
		WHERE		op.PartyID IN (	SELECT CAST (x.value AS INT) AS PartyID FROM STRING_SPLIT(@PartyIDs,',') x)
	)
	SELECT 
		STUFF((SELECT  ',' + CAST(p.PartyID  AS VARCHAR(10))
				FROM	PartyList p
				INNER JOIN statusList s ON p.StatusId = s.StatusId
			FOR XML PATH(''), TYPE
			).value('.', 'VARCHAR(MAX)')  
		,1,1,'') AS PartyIDs
)
