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
	@Minfee				MONEY,
	@Waivemonth			TINYINT,
	@GroupId			INT,
	@ProductIds			VARCHAR(1000)	= '', 
	@UserNames			VARCHAR(4000)	= '', 
	@FunctionKeys		VARCHAR(4000)	= '', 
	@ChargeInfoSettingData	VARCHAR(MAX),
	@UserId				INT, 
	@LoginIp			VARCHAR (50)	= '', 
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
								</ChargeInfoSetting>
								<ChargeInfoSetting>
									<ProductId>1</ProductId>
									<Rate>0.1</Rate>
									<Remark>create date 2019-01-08</Remark>
									<BasisOfBilling>10% of Gross Win Launched on 2019-01-08</BasisOfBilling>
									<ChargeType>1</ChargeType>
								</ChargeInfoSetting>
							</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE 
		@StartRun		DATETIME, 
		@EndRun			DATETIME, 
		@Duration		INT, 
		@LogSPData		NVARCHAR(MAX) 

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
	;MERGE dbo.LicenseeProduct3rd WITH(ROWLOCK) AS t
	USING @Products AS s
	ON (t.ProductID= s.ProductId AND t.LicenseeId = @LicenseeId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(LicenseeID, ProductID, EffectiveDate)
				VALUES(@LicenseeId, s.ProductId, @LaunchDate)
	WHEN MATCHED
		THEN UPDATE SET EffectiveDate = @LaunchDate;
	-- #Endregion LicenseeProduct3rd
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END

	EXEC LA_NonOfficialPartyLaunch @NonOfficialPartyId, @LicenseeId, @LicenseeName, @BrandName, @BaseCurrencyId
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END

	DECLARE @PartyID	INT
	SELECT @PartyID = PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName = @LicenseeName

	EXEC LA_ChargeInfoIns @PartyID, @BaseCurrencyId, @LaunchDate, @Minfee, @Waivemonth, @GroupId, @ProductIds, @ChargeInfoSettingData

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END

	-- #Region LA_UserPartyIns
	DECLARE @UserName VARCHAR(50)
	WHILE(EXISTS(SELECT 1 FROM @Users))
	BEGIN
		SELECT TOP 1 @UserName = UserName FROM @Users
		EXEC LA_UserPartyIns @UserName, @LicenseeName 

		DELETE @Users WHERE UserName = @UserName
	END
	-- #Endregion LA_UserPartyIns

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END

	-- #Region FunctionPartyIns
	DECLARE @FunctionKey NVARCHAR(100), @FunctionId INT
	WHILE(EXISTS(SELECT 1 FROM @Functions))
	BEGIN
		SELECT TOP 1 @FunctionKey = FunctionKey FROM @Functions
		EXEC LA_FunctionPartyIns @FunctionKey, @PartyID

		DELETE @Functions WHERE FunctionKey = @FunctionKey
	END
	-- #Endregion FunctionPartyIns

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Launch licensee failed. Please try again.', @ErrCode =  503
		RETURN
	END

	-- #Region: Write Log
	SET @LogSPData = CAST((SELECT
						@NonOfficialPartyId	AS '@nop',
						@LicenseeId			AS 'li',
						@LicenseeName		AS 'ln',
						@BrandName			AS 'bn',
						@BaseCurrencyId		AS 'bci',
						@LaunchDate			AS 'ld', 
						@Minfee				AS 'mf',
						@Waivemonth			AS 'wm',
						@GroupId			AS 'gi',
						@ProductIds			AS 'pis', 
						@UserNames			AS 'uns', 
						@FunctionKeys		AS 'fks', 
						@ChargeInfoSettingData	AS 'cisd'
						FOR XML PATH('z'), ROOT('r')
					) AS VARCHAR(MAX))

	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	-- Get log action
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_LaunchLicensee'

	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_LaunchLicensee'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @Duration
			, @Data = @LogSPData
			, @OldData = ''
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
			@UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = ''
			, @Duration = @Duration
	END CATCH
	-- #Endregion: Write Log
END
GO