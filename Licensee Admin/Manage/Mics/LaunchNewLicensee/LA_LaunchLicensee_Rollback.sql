/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_Rollback]
	@PartyId			INT,
	@GroupId			INT
AS
/*
	Created: 20190115@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190115@Parsons: Launch new licensee

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	-- #Region LA_LaunchLicensee_PartyIns
		UPDATE dbo.OAS_Party  
		SET OldRefID   = NULL
			,SetupName = NULL
			,PartyType = 5
			,PartyName=ISNULL(SetupName, PartyName)
		WHERE PartyID = @PartyId

		UPDATE dbo.OAS_PartyDetail  
		SET StatusId = 0
		WHERE PartyID = @PartyId
	-- #Endregion LA_LaunchLicensee_PartyIns

	-- #Region LA_LaunchLicensee_ChargeInfoIns
	DELETE cs
	FROM LA_ChargeInfo_SystemMapping cs
		INNER JOIN OAS_ChargeInfo c WITH(NOLOCK) ON cs.ChargeID = c.ChargeID
	WHERE c.FromParty = @PartyId AND c.ToParty = @GroupId

	DELETE 
	FROM OAS_ChargeInfo
	WHERE FromParty = @PartyId AND ToParty = @GroupId 
	-- #Endregion LA_LaunchLicensee_ChargeInfoIns

	-- #Region LA_LaunchLicensee_MinFeeIns
	DELETE 
	FROM LA_MinFee
	WHERE PartyId = @PartyId
	-- #Endregion LA_LaunchLicensee_MinFeeIns

	-- #Region LA_UserPartyIns
	DELETE
	FROM LA_UserParty
	WHERE PartyID = @PartyID
	-- #Endregion LA_UserPartyIns

	-- #Region FunctionPartyIns
	DELETE
	FROM LA_FunctionParty
	WHERE PartyID = @PartyID
	-- #Endregion FunctionPartyIns
END
GO