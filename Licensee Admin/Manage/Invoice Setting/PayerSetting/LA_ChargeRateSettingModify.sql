USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingModify]
	@PayerID				INT
	, @ChargeSettingXML		NVARCHAR (MAX)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @ErrorPair			NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	 Created: 20150423@Florent
	 Task : Add/ Modify Charge rate setting
	 DB: DB052.bodb_Licensee

	 Revisions:
		- 20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
		- 20150831@Bravo: fix bug - Min fee term & Basis of billing max length.
		- 20150917@Victor: Support Chinese on Settings.
		- 20151216@Bravo: Add MGC charge rate (Generic & Branded game).
		- 20170215@Scofield: Update check overlap and update system mapping
		- 20170220@bruce:	- remove update payer's base curency
							- refactor sp

	 Params:
		+ @InvoiceSettingXML: '<ChargeSettings>
								  <ChargeSetting>
									<ChargeId>1</ChargeId>
									<ProductId>1</ProductId>
									<FirstBilling>1</FirstBilling>
									<BasisBilling>1</BasisBilling>
									<BettypeRef>2001</BettypeRef>
									<Rate>1</Rate>
									<ChargeType>1</ChargeType>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
								  </ChargeSetting>
								  <ChargeSetting>
									<ChargeId>1</ChargeId>
									<ProductId>1</ProductId>
									<FirstBilling>1</FirstBilling>
									<BasisBilling>1</BasisBilling>
									<BettypeRef>2005</BettypeRef>
									<Rate>1</Rate>
									<ChargeType>1</ChargeType>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
								  </ChargeSetting>
								</ChargeSettings>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE
			, @MaxDate			DATE
	SET @startRun = GETDATE()
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_ChargeRateSettingModify'

	IF ISNULL(@ChargeSettingXML, '') = '' RETURN

	DECLARE @ChargeSetting AS TABLE (
		Idx				INT IDENTITY(1,1),
		ChargeID		INT,
		ProductId		INT,
		FirstBilling	DATE,
		BasisBilling	NVARCHAR(MAX),
		BettypeRef		INT,
		Rate			MONEY,
		ChargeType		INT,
		FromDate		DATE,
		ToDate			DATE,
		StatusId		TINYINT)

	DECLARE @ChargeRate AS TABLE (
		ChargeID	INT,
		ProductId	INT,
		BettypeRef	INT,
		FromDate	DATE,
		ToDate		DATE)

	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @ChargeSettingXML
	BEGIN TRY
		INSERT INTO @ChargeSetting(ChargeId, ProductId, FirstBilling, BasisBilling, BettypeRef, Rate, ChargeType, FromDate, ToDate, StatusId)
		SELECT ISNULL(ChargeID, 0), ProductId, CASE WHEN FirstBilling='1900-01-01' THEN NULL ELSE FirstBilling END, BasisBilling, BettypeRef, Rate, ChargeType, FromDate, ToDate, 1/*new settings*/
		FROM OPENXML(@idoc, 'ChargeSettings/ChargeSetting')
		WITH (
			 ChargeId		INT				'ChargeId'
			, ProductId		INT				'ProductId'
			, FirstBilling	DATE			'FirstBilling'
			, BasisBilling	NVARCHAR(MAX)	'BasisBilling'
			, BettypeRef	INT				'BettypeRef'
			, Rate			MONEY			'Rate'
			, ChargeType	INT				'ChargeType'
			, FromDate		DATE			'FromDate'
			, ToDate		DATE			'ToDate'
		)
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'There''s something wrong with Charge rate settings, update failed. Please try again.', @ErrCode = 701
		RETURN
	END CATCH
	EXEC sp_xml_removedocument @idoc

	-- check  0 < rate < 1
	IF EXISTS (SELECT 1 FROM @ChargeSetting WHERE Rate < 0 OR Rate > 1)
	BEGIN
		SELECT 	@ErrMsg = 'Charge rate should bewteen 0% and 100%, update failed. Please try again.', @ErrCode = 702
		RETURN
	END

	-- fromdate must less than todate
	IF EXISTS (SELECT TOP 1 1 FROM @ChargeSetting WHERE FromDate > ToDate)
	BEGIN
		SELECT @ErrMsg = 'From Date could not be later than To Date', @ErrCode = 703
		RETURN
	END

	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')

	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE ci.FromParty = @PayerID
	
	-- check overlap time charge
	INSERT INTO @ChargeRate(ChargeId, ProductId,  BettypeRef, FromDate, ToDate)
	SELECT ChargeId,ProductId, Bettype, FromDate, ToDate
	FROM dbo.LA_f_ChargeInfo(@PayerID, @MinDate, @MaxDate ,@ProductListAll, 'OA', 1)

	INSERT INTO @ChargeSetting(ChargeId, ProductId,  BettypeRef, ChargeType, FromDate, ToDate, StatusId)
	SELECT a.ChargeId, a.ProductId, a.BettypeRef, b.ChargeType, a.FromDate, a.ToDate, 0/*original settings*/
	FROM @ChargeRate a
		INNER JOIN dbo.OAS_ChargeInfo b WITH (NOLOCK) ON a.ChargeID = b.ChargeID
	WHERE a.ChargeID NOT IN (SELECT ChargeID FROM @ChargeSetting)
		AND a.ProductId IN (SELECT ProductId FROM @ChargeSetting)

	---check case Update , compare new data with old config
	IF NOT EXISTS (
		SELECT TOP 1 1
		FROM @ChargeSetting a LEFT JOIN @ChargeSetting b ON a.Idx != b.Idx AND a.ChargeType = b.ChargeType AND a.ProductId = b.ProductId AND (
			a.ProductId NOT IN (14,17) OR
			a.BettypeRef = b.BettypeRef
		)
		WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
					OR a.ToDate BETWEEN b.FromDate AND b.ToDate
					OR b.FromDate BETWEEN a.FromDate AND a.ToDate
					OR b.ToDate BETWEEN a.FromDate AND a.ToDate
				))
	BEGIN
		-- remove original settings
		DELETE @ChargeSetting WHERE StatusId = 0

		-- new product
		UPDATE s SET s.StatusId = 2 /*new product*/
		FROM @ChargeSetting s
		WHERE s.ProductID NOT IN (SELECT ProductId FROM @ChargeRate)

		-- write log
		-- build log string
		SET @xml = (
			SELECT	ci.ChargeId				AS '@c'
					, ci.FromParty			AS '@fp'
					, ci.ProductId			AS '@tp'
					, ci.FirstOfBilling		AS '@fb'
					, ci.BasisOfBilling		AS '@bb'
					, ci.Rate				AS '@r'
					, ci.ChargeType			AS '@ct'
					, ci.FromDate			AS '@fd'
					, ci.ToDate				AS '@td'
			FROM @ChargeSetting  cs
				INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID
			FOR XML PATH('z'), ROOT('r')
		)

		DECLARE @MergeResult TABLE(ChargeId INT, ProductId INT, [$action] VARCHAR(20))
		DECLARE @ToParty INT, @ParentChargeID INT, @Remark VARCHAR(200) = ''

		SELECT TOP 1 @ToParty = c.ToParty, @ParentChargeID = c.ParentChargeID
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE FromParty = @PayerID
		ORDER BY FromDate DESC

		SET @Remark = @Remark + 'created date: ' + CONVERT(VARCHAR(20), GETDATE(), 101)

		-- update charege info (product without bettype ref)
		;MERGE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) AS t
		USING @ChargeSetting s ON t.ChargeID = s.ChargeID
		WHEN MATCHED THEN UPDATE SET t.FirstOfBilling = s.FirstBilling
			, t.BasisOfBilling = s.BasisBilling
			, t.Rate = s.Rate
			, t.FromDate = s.FromDate
			, t.ToDate = s.ToDate
		WHEN NOT MATCHED BY TARGET AND (ISNULL(s.BettypeRef, 0) = 0 OR (s.BettypeRef = 2001 AND s.ProductId IN(14,17))/*insert a reference charge rate setting for 14,17*/)
			THEN INSERT(ProductID, FromParty, ToParty, ParentChargeID, Rate, ChargeType, FromDate, ToDate, Remark, FirstOfBilling, BasisOfBilling)
			VALUES(s.ProductId, @PayerID, @ToParty, @ParentChargeID, s.Rate, s.ChargeType, s.FromDate, s.ToDate, @Remark, s.FirstBilling, s.BasisBilling)
		OUTPUT INSERTED.ChargeID, INSERTED.ProductId, $action INTO @MergeResult;

		-- update new charge id to @ChargeSetting
		UPDATE c SET c.ChargeID = ci.ChargeID
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		INNER JOIN @MergeResult m ON m.ChargeId = ci.ChargeID
		INNER JOIN @ChargeSetting c ON ci.ProductID = c.ProductId AND c.FromDate = ci.FromDate
		WHERE m.[$action]='INSERT'

		-- update charege info & charge info sub (MGC)
		;MERGE dbo.OAS_ChargeInfoSub WITH (ROWLOCK, UPDLOCK) AS t
		USING @ChargeSetting s ON t.ChargeIdRef = s.ChargeID AND t.BettypeRef = s.BettypeRef AND ISNULL(s.BettypeRef, 0) != 0
		WHEN MATCHED THEN
			UPDATE SET t.FirstOfBilling = s.FirstBilling
				, t.BasisOfBilling = s.BasisBilling
				, t.Rate = s.Rate
				, t.FromDate = s.FromDate
				, t.ToDate = s.ToDate
		WHEN NOT MATCHED BY TARGET AND s.ProductId IN (14,17) THEN
			INSERT(ProductID, FromParty, ToParty, ParentChargeID, BettypeRef, Rate, ChargeType, FromDate, ToDate, FirstOfBilling, BasisOfBilling, ChargeIdRef)
			VALUES(s.ProductId, @PayerID, @ToParty, @ParentChargeID, s.BettypeRef, s.Rate, s.ChargeType, s.FromDate, s.ToDate, s.FirstBilling, s.BasisBilling, s.ChargeID);

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701
			RETURN
		END

		-- update system mapping
		INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT ChargeID, 2 FROM @MergeResult WHERE [$action]='INSERT'

		IF @ToParty = 1 -- ONEWorks
		BEGIN
			INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
			SELECT m.ChargeID, 4
			FROM @MergeResult m
			WHERE m.ProductId IN (SELECT p.ProductId FROM dbo.LRF_f_Products3rd('SB,NG,VS,LC,AGC,GD,VG') p)
				AND m.[$action] = 'INSERT'
		END

		-- add licensee/function permission
		WHILE EXISTS (SELECT TOP 1 1 FROM @ChargeSetting WHERE StatusId = 2)
		BEGIN
			DECLARE @ProductId INT = (SELECT TOP 1 ProductId FROM @ChargeSetting WHERE StatusId = 2)
			EXEC dbo.LA_FunctionPartiesPermission @PartyId=@PayerID, @ProductId=@ProductId
			UPDATE  @ChargeSetting SET StatusId = 1 WHERE StatusId = 2 AND ProductId = @ProductId
		END

		IF @@ERROR <> 0
		BEGIN
			--rolback
			DELETE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK)
			WHERE ChargeID IN (SELECT ChargeID FROM @MergeResult WHERE [$action] = 'INSERT')

			SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 701
			RETURN
		END

		SET @logSPData = (
			SELECT	ci.ChargeId				AS '@c'
					, ci.FromParty			AS '@fp'
					, cs.ProductId			AS '@tp'
					, cs.FirstBilling		AS '@fb'
					, cs.BasisBilling		AS '@bb'
					, cs.Rate				AS '@r'
					, cs.ChargeType			AS '@ct'
					, cs.FromDate			AS '@fd'
					, cs.ToDate				AS '@td'
			FROM @ChargeSetting  cs
				LEFT JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID
			FOR XML PATH('z'), ROOT('r')
		)
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

		--Write Log
		BEGIN TRY
			EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog
				@UserId = @UserID
				, @IP = @LoginIP
				, @LicenseeID = 0
				, @CurrencyID = 0
				, @SPName = 'LA_ChargeRateSettingModify'
				, @CustId = 0
				, @ActionId = @ActionID
				, @Duration = @duration
				, @Data = @logSPData
				, @OldData = @logSPDataOld
		END TRY
		BEGIN CATCH
			EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
				@UserID = @UserID
				, @CustID = 0
				, @ActionID = @ActionID
				, @TrackingValue = @LogSPData
				, @TrackingValue2 = @logSPDataOld
				, @duration = @duration
		END CATCH
	END
	ELSE
	BEGIN
		SELECT @ErrorPair = COALESCE(@ErrorPair + ',' + '( ' +CAST(a.Idx AS VARCHAR)+','+ CAST(b.Idx AS VARCHAR) +' )', '( ' +CAST(a.Idx AS VARCHAR)+', '+ CAST(b.Idx AS VARCHAR) +' )')
		FROM @ChargeSetting a LEFT JOIN @ChargeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate)
		SET @ErrorPair = SUBSTRING(@ErrorPair, 0, LEN(@ErrorPair)/2 +1)
		--raise error
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date'
			, @ErrCode = 700
		RETURN
	END
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_ChargeRateSettingModify] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_ChargeRateSettingModify] TO bodbAdminNet
GO