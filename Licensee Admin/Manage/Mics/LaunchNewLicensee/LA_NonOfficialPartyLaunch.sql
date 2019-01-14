/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_NonOfficialPartyLaunch]
	@NonOfficialPartyId	INT,
	@LicenseeId			INT,
	@LicenseeName		VARCHAR(50),
	@BrandName			VARCHAR(100),
	@BaseCurrencyId		TINYINT
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190107@Parsons: Launch new licensee

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	-- #Region OAS_Party
	IF(@NonOfficialPartyId > 0)
	BEGIN
		UPDATE dbo.OAS_Party  
		SET OldRefID   = @LicenseeId
			,SetupName = PartyName
			,PartyType = 1
			,PartyName = @LicenseeName
		WHERE PartyID = @NonOfficialPartyId
	END
	ELSE
	BEGIN
		INSERT INTO dbo.OAS_Party(PartyName, PartyType, OldRefID)
		VALUES(@LicenseeName, 1, @LicenseeId)
		
		SET @NonOfficialPartyId = SCOPE_IDENTITY()
	END
	-- #Endregion OAS_Party

	-- #Region OAS_PartyDetail
	IF EXISTS(SELECT 1 FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE PartyID = @NonOfficialPartyId)
	BEGIN
		UPDATE dbo.OAS_PartyDetail  
		SET BrandName = @BrandName,
			BaseCurrencyId = @BaseCurrencyId,
			StatusId = 1
		WHERE PartyID = @NonOfficialPartyId
	END
	ELSE
	BEGIN
		INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, BaseCurrencyId, StatusId)
		SELECT @NonOfficialPartyId, IsDeposit, @BrandName, CompanyName, IsAllowedMemberComm, @BaseCurrencyId, 1
		FROM dbo.licensees WITH (NOLOCK)
		WHERE LicenseeID = @LicenseeId
	END
	-- #Endregion OAS_PartyDetail
END
GO