/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee]
	@NonOfficialPartyId	INT,
	@LicenseeId			INT,
	@LicenseeName		VARCHAR(50),
	@BrandName			VARCHAR(100),
	@BaseCurrencyId		TINYINT,
	@LaunchDate			DATE, 
	@GroupId			INT,
	@ProductIds			VARCHAR(1000)	= '', 
	@UserNames			VARCHAR(4000)	= '', 
	@FunctionKeys		VARCHAR(4000)	= '', 
	@ChargeInfoSettingData	VARCHAR(MAX),
	@MinFeeSettingData	VARCHAR(MAX),
	@UserId				INT, 
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
						@ChargeInfoSettingData = '<Root>
								<ChargeInfoSetting>
									<ProductId>0</ProductId>
									<Rate>0.15</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>15% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
								</ChargeInfoSetting>
							</Root>'

							@MinFeeSettingData = '<Root>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>1</FeeTypeId>
									<FeeAmount>5000</FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20500101</ToDate>
									<MinFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinFeeTerm>
									<Priority>1</Priority>
								</MinFeeSetting>
								<MinFeeSetting>
									<ProductId>0</ProductId>
									<FeeTypeId>2</FeeTypeId>
									<FeeAmount></FeeAmount>
									<BaseCurrencyID>6</BaseCurrencyID>
									<FromDate>20190108</FromDate>
									<ToDate>20190407</ToDate>
									<MinFeeTerm></MinFeeTerm>
									<Priority>2</Priority>
								</MinFeeSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE 
		@StartRun		DATETIME, 
		@EndRun			DATETIME, 
		@Duration		INT, 
		@Doing			NVARCHAR(MAX)

	SET @StartRun = GETDATE()

	DECLARE @Products	TABLE (ProductId INT)
	DECLARE @Users		TABLE (UserName VARCHAR(50))
	DECLARE @Functions	TABLE (FunctionKey NVARCHAR(100))
	
	INSERT INTO @Products(ProductId)
	SELECT val FROM bodb02.dbo.strSplit(@ProductIds, ',')

	INSERT INTO @Users(UserName)
	SELECT val FROM bodb02.dbo.strSplit(@UserNames, ',')

	INSERT INTO @Functions(FunctionKey)
	SELECT val FROM bodb02.dbo.strSplit(@FunctionKeys, ',')

	-- #Region LicenseeProduct3rd
	UPDATE dbo.LicenseeProduct3rd
	SET EffectiveDate = @LaunchDate
	WHERE LicenseeId = @LicenseeId
	-- #Endregion LicenseeProduct3rd
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert/Update LicenseeProduct3rd failed. Please try again.', @ErrCode =  503
		RETURN
	END

	EXEC LA_LaunchLicensee_PartyIns @NonOfficialPartyId, @LicenseeId, @LicenseeName, @BrandName, @BaseCurrencyId, @ErrCode OUTPUT, @ErrMsg OUTPUT 
	
	DECLARE @PartyID	INT
	SELECT @PartyID = PartyID FROM OAS_Party WITH(NOLOCK) WHERE PartyName = @LicenseeName AND (ISNULL(@NonOfficialPartyId, 0) = 0 OR PartyID = @NonOfficialPartyId)

	IF @ErrCode = 0
	BEGIN
		EXEC LA_LaunchLicensee_ChargeInfoIns @PartyID, @GroupId, @ChargeInfoSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	
	IF @ErrCode = 0
	BEGIN
		EXEC LA_LaunchLicensee_MinFeeIns @PartyID, @BaseCurrencyId, @MinFeeSettingData, @ErrCode OUTPUT, @ErrMsg OUTPUT
	END
	
	IF @ErrCode = 0
	BEGIN
		-- #Region UserPartyIns
		DECLARE @UserName VARCHAR(50)
		WHILE(EXISTS(SELECT 1 FROM @Users))
		BEGIN
			SELECT TOP 1 @UserName = UserName FROM @Users

			INSERT INTO LA_UserParty (UserID, PartyID, Modifydate, Modifier, StatusID)
			SELECT UserID, @PartyID, GETDATE(), @UserID, 1
			FROM dbo.LA_User WITH (NOLOCK) 
			WHERE Username = @UserName

			DELETE @Users WHERE UserName = @UserName

			IF @@ERROR <> 0
			BEGIN
				SELECT @ErrMsg = 'Insert LA_UserParty failed. Please try again.', @ErrCode =  503
				DELETE @Users
			END
		END
		-- #Endregion UserPartyIns
	END

	IF @ErrCode = 0
	BEGIN
		-- #Region FunctionPartyIns
		DECLARE @FunctionKey NVARCHAR(100), @FunctionId INT
		WHILE(EXISTS(SELECT 1 FROM @Functions))
		BEGIN
			SELECT TOP 1 @FunctionKey = FunctionKey FROM @Functions

			INSERT INTO dbo.LA_FunctionParty (FunctionID, PartyID)
			SELECT FunctionID, @PartyID
			FROM dbo.LA_Function WITH (NOLOCK) 
			WHERE FunctionKey = @FunctionKey

			DELETE @Functions WHERE FunctionKey = @FunctionKey

			IF @@ERROR <> 0
			BEGIN
				SELECT @ErrMsg = 'Insert LA_FunctionParty failed. Please try again.', @ErrCode =  503
				DELETE @Functions
			END
		END
		-- #Endregion FunctionPartyIns
	END

	IF @ErrCode <> 0
	BEGIN
		EXEC LA_LaunchLicensee_Rollback @PartyID, @GroupId
		RETURN
	END

	-- #Region: Write Log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	SET @Doing =(SELECT	@NonOfficialPartyId	AS NonOfficialPartyId,
						@LicenseeId			AS LicenseeId,
						@LicenseeName		AS LicenseeName,
						@BrandName			AS BrandName,
						@BaseCurrencyId		AS BaseCurrencyId,
						@LaunchDate			AS LaunchDate, 
						@GroupId			AS GroupId,
						@ProductIds			AS ProductIds, 
						@UserNames			AS UserNames, 
						@FunctionKeys		AS FunctionKeys, 
						@ChargeInfoSettingData	AS ChargeInfoSettingData,
						@MinFeeSettingData	AS MinFeeSettingData
						FOR XML PATH('')) 

	EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_UserControl
		@Custid = 0,
		@Doing = @Doing,
		@Userid = @UserId,
		@Typeid = 0,
		@Actionid = 5535,
		@Duration = @Duration

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = ERROR_MESSAGE() , @ErrCode = 503
	END
	-- #Endregion: Write Log
END
GO