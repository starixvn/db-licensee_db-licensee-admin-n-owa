/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PayerSettingModify]
	@PayerID				INT	
	, @LaunchDate			DATE = NULL
	, @SuspendedDate		DATE = NULL
	, @TerminatedDate		DATE = NULL
	, @ChargeSettingXML		NVARCHAR (MAX)
	, @MinFeeSettingXML		NVARCHAR (MAX)
	, @WaiveSettingXML		NVARCHAR (MAX)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT	
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20150918@Victor: Support Chinese on Settings
		- 20170220@bruce: update payer settings [#70050]
		- 20180706@bruce: enhance discount group [#94282]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20200831@Mason: Remove redundant code of @PayerGroupId [#138249]
		- 20210318@Mason: Change Base Currency Of Licensee [#151466]
		- 20220118@Percy: Add Licensee Status Setting [RedmineID: #166751]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]

	 Params:	
		+ @ChargeSettingXML:
					<ChargeSettings>
						<ChargeSetting>
							<ChargeId>3483</ChargeId>
							<ProductId>2</ProductId>
							<FirstBilling>20130101</FirstBilling>
							<BasisBilling>15% of Gro1ss Win</BasisBilling>
							<BettypeRef>0</BettypeRef>
							<Rate>0.9</Rate><
							ChargeType>1</ChargeType>
							<FromDate>20180801</FromDate>
							<ToDate>20250531</ToDate>
							<ChargeSettingsDetails>
										<ChargeSettingsDetail>
											<CurrencyId>1</CurrencyId>
											<Rate>0.2</Rate>
										</ChargeSettingsDetail>
										<ChargeSettingsDetail>
											<CurrencyId>2</CurrencyId>
											<Rate>0.3</Rate>
										</ChargeSettingsDetail>
									<ChargeSettingsDetails>
						</ChargeSetting>
					</ChargeSettings>
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ProductListAll VARCHAR(100) = '', @MinDate DATE, @MaxDate DATE, @SiteName VARCHAR(20) ='', @InputPT VARCHAR(MAX) = '', @ChargeRateXML XML, @ChargeSettingXMLOUT XML
	
	DECLARE @MinFeeInsertedList VARCHAR(100), @WaiveInsertedList VARCHAR(100)

	-- Update LaunchDate/SuspendedDate/TerminatedDate
	DECLARE @Old_LaunchDate DATE, @Old_SuspendedDate DATE, @Old_TerminatedDate DATE
	SELECT  @Old_LaunchDate = LaunchDate, @Old_SuspendedDate = SuspendedDate, @Old_TerminatedDate = TerminatedDate
	FROM dbo.OAS_PartyDetail WITH (NOLOCK)
	WHERE PartyId = @PayerId

	BEGIN TRY
		UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
		SET LaunchDate = @LaunchDate, SuspendedDate = @SuspendedDate, TerminatedDate = @TerminatedDate
		WHERE PartyId = @PayerId
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 101, @ErrMsg = 'Update failed. Please try again.'
		RETURN
	END CATCH

	--Minfee
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @MinFeeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @MinFeeInsertedList  OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			RETURN
		END
	--Waive
	EXEC dbo.LA_MinFeeSettingModify
		@PayerID				= @PayerID
		, @MinFeeSettingXML		= @WaiveSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode		OUTPUT
		, @ErrMsg				= @ErrMsg		OUTPUT
		, @MinfeeInsertedList	= @WaiveInsertedList OUTPUT
	IF @ErrCode <> 0 
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			RETURN
		END

	--Modify Chargerate Setting
	EXEC dbo.LA_ChargeRateSettingModify
		@PayerID				= @PayerID
		, @ChargeSettingXML		= @ChargeSettingXML
		, @UserID				= @UserID
		, @LoginIP				= @LoginIP
		, @ErrCode				= @ErrCode OUTPUT
		, @ErrMsg				= @ErrMsg OUTPUT		
		, @ChargeSettingXMLOUT  = @ChargeSettingXMLOUT OUTPUT

	IF @ErrCode <> 0 
		BEGIN
			--Rollback LaunchDate/SuspendedDate/TerminatedDate
			UPDATE dbo.OAS_PartyDetail WITH (ROWLOCK)
			SET LaunchDate = @Old_LaunchDate, SuspendedDate = @Old_SuspendedDate, TerminatedDate = @Old_TerminatedDate
			WHERE PartyId = @PayerId

			--Rollback Minfee
			IF ISNULL(@MinFeeInsertedList, 0) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@MinFeeInsertedList, ','))
			--Rollback waive
			IF ISNULL(@WaiveInsertedList, 0 ) <> 0
				DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) WHERE PartyId = @PayerID AND MinFeeId IN (SELECT value FROM STRING_SPLIT(@WaiveInsertedList, ','))
			RETURN
		END

	-- Update on NAP
	DECLARE @ChargeRate TABLE (ChargeID INT, ProductId INT, ProductName VARCHAR(50), Rate MONEY, FromDate DATETIME, ToDate DATETIME, IsValid BIT DEFAULT(1))

	DECLARE @ChargeRateDetail TABLE (ChargeID INT, CurrencyId INT, Rate MONEY)

	INSERT INTO @ChargeRate (ChargeId, FromDate, ToDate, ProductId, Rate)
	SELECT
		t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeId
		,t.c.value('(FromDate/text())[1]', 'DATETIME') AS FromDate
		,t.c.value('(ToDate/text())[1]', 'DATETIME') AS ToDate
		,t.c.value('(ProductId/text())[1]', 'INT') AS ProductId
		,t.c.value('(Rate/text())[1]', 'MONEY') AS Rate
	FROM @ChargeSettingXMLOUT.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingXMLOUT = NULL))

	INSERT INTO @ChargeRateDetail (ChargeId, CurrencyId, Rate)
	SELECT
		t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeId
		,t1.c.value('(CurrencyId/text())[1]', 'INT') AS CurrencyId
		,t1.c.value('(Rate/text())[1]', 'MONEY') AS Rate
	FROM @ChargeSettingXMLOUT.nodes('ChargeSettings/ChargeSetting') AS t(c)
	CROSS APPLY t.c.nodes('ChargeSettingsDetails/ChargeSettingsDetail') t1(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingXMLOUT = NULL))

	UPDATE @ChargeRate
		SET IsValid = 0
	WHERE GETDATE() NOT BETWEEN FromDate AND ToDate

	DELETE r 
	FROM @ChargeRate r
		INNER JOIN OAS_ChargeInfo c WITH(NOLOCK) ON r.ChargeID = c.ChargeID
	WHERE r.Rate = c.Rate AND r.IsValid = 1

	DELETE FROM @ChargeRate WHERE ProductId IN (14, 17)

	SELECT @SiteName = l.LicenseeName
	FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.Licensees l WITH(NOLOCK) ON p.OldRefID = l.LicenseeID
	WHERE l.IsDeposit = 1 AND p.PartyID = @PayerID

	UPDATE c
		SET c.ProductId = CASE WHEN c.ProductId = 0 THEN 1 ELSE p.ProductId END, c.ProductName = CASE WHEN c.ProductId = 0 THEN 'Sportsbook' ELSE pr.ProductName END
	FROM @ChargeRate c
		LEFT JOIN dbo.Product3rd pr WITH(NOLOCK) ON pr.Productid = c.ProductId
		LEFT JOIN DBPRO.bodb02.dbo.Products p WITH (NOLOCK) ON p.ProductPrefix = pr.ProductPrefix

	;WITH CTE_ChargeId AS 
	(
		SELECT DISTINCT ChargeID, ProductId, ProductName FROM @ChargeRate WHERE IsValid = 1
	),CTE_Currency AS
	(
		SELECT cr.ChargeID, cr.CurrencyID, c.ProductId, c.ProductName
		FROM dbo.LA_ChargeRateByCurrency cr WITH(NOLOCK)
			INNER JOIN CTE_ChargeId c ON c.ChargeID = cr.ChargeID
				LEFT JOIN @ChargeRateDetail d ON d.ChargeID = cr.ChargeID AND d.CurrencyId = cr.CurrencyID AND d.Rate = cr.Rate
	)
	INSERT INTO @ChargeRate (ChargeID, ProductId, ProductName, CurrencyId, Rate, IsValid)
	SELECT ChargeID, ProductId, ProductName, CurrencyID, 2, 1 -- 2 : not update
	FROM CTE_Currency

	SELECT @InputPT = CONVERT(VARCHAR(MAX), 
	(
		SELECT 
			ProductId AS '@PID'
			,CurrencyId AS '@CID'
			,1 - Rate AS '@PT' -- [-1] : not update
		FROM @ChargeRate 
		WHERE IsValid = 1
		FOR XML PATH ('PT'), ROOT('ROOT')
	))

	IF @SiteName <> '' AND @InputPT <> ''
	BEGIN
		EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd
			@Site = @SiteName
			,@InputPT = @InputPT
			,@UserID = @UserID
			,@IP = @LoginIP
			,@ErrCode = @ErrCode OUTPUT
			,@ErrMsg = @ErrMsg OUTPUT
	END

	IF (@ErrCode  <> 0 OR EXISTS (SELECT 1 FROM @ChargeRate WHERE IsValid = 0)) AND @SiteName <> ''
	BEGIN
		IF @ErrCode <> 0
			RETURN
		
		SELECT 
			@ErrCode = 101
			,@ErrMsg =  ISNULL(@ErrMsg, '') + ProductName + ': NAP PT update failed for charge rate value ' + CONVERT(VARCHAR(30), Rate * 100) + '% due to it''s not current charge rate' + CHAR(13)
		FROM @ChargeRate
		WHERE IsValid = 0
		RETURN
	END

END
GO