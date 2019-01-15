/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_PartyIns]
	@NonOfficialPartyId	INT,
	@LicenseeId			INT,
	@LicenseeName		VARCHAR(50),
	@BrandName			VARCHAR(100),
	@BaseCurrencyId		TINYINT,
	@ErrCode			INT				= 0		OUTPUT, 
	@ErrMsg				VARCHAR(4000)	= ''	OUTPUT
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
		IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID = @NonOfficialPartyId) 
		BEGIN
			SELECT @ErrMsg = 'Party not found. Please try again.', @ErrCode =  505
			RETURN
		END

		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID <> @NonOfficialPartyId AND PartyName = @LicenseeName) 
		BEGIN
			SELECT @ErrMsg = 'Party name has already been existed. Please try again.', @ErrCode =  506
			RETURN
		END

		UPDATE dbo.OAS_Party  
		SET OldRefID   = @LicenseeId
			,SetupName = PartyName
			,PartyType = 1
			,PartyName = @LicenseeName
		WHERE PartyID = @NonOfficialPartyId
	END
	ELSE
	BEGIN
		IF EXISTS (SELECT 1 FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @LicenseeName AND PartyType <> 1) 
		BEGIN
			UPDATE dbo.OAS_Party
			SET PartyType = 1, OldRefID = @LicenseeId
		END
		ELSE
		BEGIN
			INSERT INTO dbo.OAS_Party(PartyName, PartyType, OldRefID)
			VALUES(@LicenseeName, 1, @LicenseeId)
		END
	END
	-- #Endregion OAS_Party

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert/Update OAS_Party failed. Please try again.', @ErrCode =  503
		RETURN
	END

	-- #Region OAS_PartyDetail
	DECLARE @PartyId INT
	SELECT @PartyId = PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @LicenseeName
	IF EXISTS(SELECT 1 FROM dbo.OAS_PartyDetail WITH (NOLOCK) WHERE PartyID = @PartyId)
	BEGIN
		UPDATE dbo.OAS_PartyDetail  
		SET BrandName = @BrandName,
			BaseCurrencyId = @BaseCurrencyId,
			StatusId = 1
		WHERE PartyID = @PartyId
	END
	ELSE
	BEGIN
		INSERT INTO dbo.OAS_PartyDetail (PartyID, IsDeposit, BrandName, CompanyName, IsAllowedMemberComm, BaseCurrencyId, StatusId)
		SELECT @PartyId, IsDeposit, @BrandName, CompanyName, IsAllowedMemberComm, @BaseCurrencyId, 1
		FROM dbo.licensees WITH (NOLOCK)
		WHERE LicenseeID = @LicenseeId
	END
	-- #Endregion OAS_PartyDetail

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert/Update OAS_PartyDetail failed. Please try again.', @ErrCode =  503
		RETURN
	END
END
GO