/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
ALTER PROCEDURE [dbo].[LA_ChargeRateSettingModify]
	@PayerID				INT
	,@ChargeSettingXML		NVARCHAR (MAX)
	,@UserID				INT
	,@LoginIP				VARCHAR (50)	= ''
	,@ErrCode				INT				= 0	 OUTPUT
	,@ErrMsg				NVARCHAR(1000)	= '' OUTPUT
	,@ErrorPair			    NVARCHAR(1000)	= '' OUTPUT
	,@ChargeSettingXMLOUT	XML = NULL OUTPUT
AS
/*
	 Created: 20150423@Florent
	 Task: Add/ Modify Charge rate setting
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		- 20150703@Florent: store BaseCurrencyId from OAS_ChargeInfo to OAS_PartyDetail
		- 20150831@Bravo: fix bug - Min fee term & Basis of billing max length.
		- 20150917@Victor: Support Chinese on Settings.
		- 20151216@Bravo: Add MGC charge rate (Generic & Branded game).
		- 20170215@Scofield: Update check overlap and update system mapping
		- 20170220@bruce:	- remove update payer's base curency
							- refactor sp
		- 20170301@Scofield: update effective date for LicenseeProduct3rd
		- 20170307@Scofield: update to not save rate, basic billing, first billing for MGC[#70050]
		- 20170407@Scofield: log dataold [#73310]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658] 
		- 20190801@Parsons: Validate billing configuration [#109600]
		- 20200417@Parsons: Indo 4D Integration [#130910]
		- 20200619@Happy: Increase the length of @ProductCode params [#128570]
		- 20211101@Percy: Don't add new SB Rate if Licensee is belong to discount group on Lic WL [RedmineID: #162158]
		- 20220831@Malcolm: Automate the PT adjustment when the charge rate is changed [RemineID: #171705]

	 Params:
		+ @ChargeSettingXML: '<ChargeSettings>
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
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML, @ChargeSettingsXML XML
	DECLARE @ProductListAll		VARCHAR(500) = ''
			, @MinDate			DATE
			, @MaxDate			DATE
	SET @startRun = GETDATE()

	IF ISNULL(@ChargeSettingXML, '') = '' RETURN

	SELECT @ChargeSettingsXML = CONVERT(XML, @ChargeSettingXML)

	DECLARE @ChargeSetting AS TABLE 
	(
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
		StatusId		TINYINT,
		IsChangedRate	BIT DEFAULT(1),
		IsChangedDate	BIT DEFAULT(0)
	)

	DECLARE @ChargeRate AS TABLE (ChargeID INT, ProductId INT, BettypeRef INT, FromDate DATE, ToDate DATE)

	INSERT INTO @ChargeSetting (ChargeID ,ProductId ,FirstBilling, BasisBilling, BettypeRef, Rate, ChargeType, FromDate, ToDate, StatusId)
	SELECT	t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeID,
			t.c.value('(ProductId/text())[1]', 'INT') AS ProductId,
			t.c.value('(FirstBilling/text())[1]', 'DATE') AS FirstBilling,
			t.c.value('(BasisBilling/text())[1]', 'NVARCHAR(MAX)') AS BasisBilling,
			t.c.value('(BettypeRef/text())[1]', 'INT') AS BettypeRef,
			t.c.value('(Rate/text())[1]', 'MONEY') AS Rate,			
			t.c.value('(ChargeType/text())[1]', 'INT') AS ChargeType,		
			t.c.value('(FromDate/text())[1]', 'DATE') AS FromDate,		
			t.c.value('(ToDate/text())[1]', 'DATE') AS ToDate,	
			1 AS StatusId
	FROM @ChargeSettingsXML.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingsXML = NULL)) 

	UPDATE c
		SET c.IsChangedRate = CASE WHEN c.Rate = ci.Rate THEN 0 ELSE 1 END
			,c.IsChangedDate = CASE WHEN ci.FromDate <> c.FromDate OR ci.ToDate <> c.ToDate THEN 1 ELSE 0 END
	FROM @ChargeSetting c
		INNER JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.ChargeID = c.ChargeID

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

		-- Do not allow to add new Sportsbook charge rate if Licensee is belonging an active discount group on Licensee Win Loss
		DECLARE @CutOffDate DATE = dbo.LA_f_DiscountByGrossWin_CutOffDate()

		IF EXISTS (
			SELECT 1
			FROM @ChargeSetting s
				INNER JOIN (
					SELECT h.FromDate, h.ToDate
					FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
						INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
					WHERE h.DiscountGroupType = 13 -- Discount group on Lic WL
						AND h.FromDate >= @CutOffDate
						AND a.PartyId = @PayerId
				) d ON s.FromDate <= d.ToDate AND s.ToDate >= d.ToDate
			WHERE s.ChargeId = 0 AND s.ProductId = 0 -- insert new SB Rate
		)
		BEGIN
			SELECT @ErrMsg = 'Licensee is in a discount group, please remove them out of it before adding new Sportsbook charge rate.', @ErrCode = 704
			RETURN
		END

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
		SET @logSPDataOld = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"');

		DECLARE @MergeResult TABLE(ChargeId INT, ProductId INT, [$action] VARCHAR(20))
		DECLARE @ToParty INT, @ParentChargeID INT, @Remark VARCHAR(200) = ''
		
		SELECT TOP 1 @ToParty = c.ToParty, @ParentChargeID = c.ParentChargeID
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE FromParty = @PayerID AND c.ToParty IN (1, 9, 11, 98)
		ORDER BY FromDate DESC
		
		SET @Remark = @Remark + 'created date: ' + CONVERT(VARCHAR(20), GETDATE(), 101)

		-- update charege info (product without bettype ref)
		;MERGE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK) AS t
		USING @ChargeSetting s ON t.ChargeID = s.ChargeID
		WHEN MATCHED AND (s.ProductId NOT IN (14,17) OR s.BettypeRef = 2001)
			THEN UPDATE SET t.FirstOfBilling = s.FirstBilling
			, t.BasisOfBilling = s.BasisBilling
			, t.Rate = s.Rate
			, t.FromDate = s.FromDate
			, t.ToDate = s.ToDate
		WHEN NOT MATCHED BY TARGET AND (s.ProductId NOT IN (14,17) OR s.BettypeRef = 2001)
			THEN INSERT(ProductID, FromParty, ToParty, ParentChargeID, ChargeType, FromDate, ToDate, Remark, Rate, FirstOfBilling, BasisOfBilling)
			VALUES(s.ProductId, @PayerID, @ToParty, @ParentChargeID, s.ChargeType, s.FromDate, s.ToDate, @Remark, 
				CASE WHEN (s.BettypeRef = 2001) THEN NULL ELSE s.Rate END, 
				CASE WHEN (s.BettypeRef = 2001) THEN NULL ELSE s.FirstBilling END, 
				CASE WHEN (s.BettypeRef = 2001) THEN NULL ELSE s.BasisBilling END)
		OUTPUT INSERTED.ChargeID, INSERTED.ProductId, $action INTO @MergeResult;

		-- update new charge id to @ChargeSetting
		UPDATE c SET c.ChargeID = ci.ChargeID
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		INNER JOIN @MergeResult m ON m.ChargeId = ci.ChargeID
		INNER JOIN @ChargeSetting c ON ci.ProductID = c.ProductId AND c.FromDate = ci.FromDate AND c.ChargeType = ci.ChargeType 
		WHERE m.[$action]='INSERT'
		
		-- update effective date for LicenseeProduct3rd
		DECLARE @EffectiveDates TABLE (LicenseeId INT, ProductId INT, EffectiveDate SMALLDATETIME)
		
		INSERT INTO @EffectiveDates (LicenseeId, ProductId, EffectiveDate)
		SELECT tmpLicensees.LicenseeID, tmpDates.ProductId, MIN(tmpDates.FromDate)
		FROM 		
			(SELECT @PayerID AS PayerId, c.ProductId, c.FromDate
			FROM @MergeResult m
			INNER JOIN @ChargeSetting c ON m.ChargeId = c.ChargeID
			WHERE m.[$action]='INSERT') tmpDates
		INNER JOIN
			(SELECT
				@PayerId AS PayerId,
				CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID
				ELSE lb.LabelID END AS LicenseeID
			FROM OAS_Party p
			LEFT JOIN OAS_PartyDetail pd ON p.PartyID = pd.PartyID
			LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
			WHERE p.PartyID = @PayerId) tmpLicensees
		ON tmpDates.PayerId = tmpLicensees.PayerId
		GROUP BY tmpLicensees.LicenseeID, tmpDates.ProductId
		
		UPDATE lp
		SET lp.EffectiveDate = ed.EffectiveDate
		FROM dbo.LicenseeProduct3rd lp
		INNER JOIN @EffectiveDates ed ON lp.LicenseeID = ed.LicenseeId AND lp.ProductID = ed.ProductId
		WHERE lp.EffectiveDate IS NULL		

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

		/*Insert Invoice Setting*/
		DECLARE @BillingGroupName NVARCHAR(50), @BillerId INT
		SELECT @BillingGroupName = PartyName
		FROM dbo.OAS_Party WITH(NOLOCK)
		WHERE PartyId = @ToParty 
		
		SELECT @BillerId = PartyId
		FROM dbo.LA_BillerInfo WITH(NOLOCK)
		WHERE BillerName = CASE @BillingGroupName
							WHEN 'Boping' THEN @BillingGroupName
							WHEN 'Zelianta' THEN @BillingGroupName + ' Limited'
							ELSE '' END

		IF ISNULL(@BillerId, 0) <> 0
			INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
			SELECT @PayerID, @BillerId, ProductId, InvTypeId, InvTemplateId, 0 AS BankId, 1 AS ActiveAddress
			FROM (
				SELECT InvTemplateId, InvTemplateName
					,CASE InvTemplateName
						WHEN @BillingGroupName THEN 1 -- Software Data & Licensing Fees
						WHEN 'Credit' THEN 4 -- Credit Note
						ELSE 5 -- Debit Note
						END AS InvTypeId
				FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
				WHERE 1 = CASE InvTemplateName
							WHEN @BillingGroupName THEN 1
							WHEN 'Credit' THEN 1
							WHEN 'Debit' + CASE WHEN @BillingGroupName = 'Zelianta' THEN '-Zelianta' ELSE '' END THEN 1
							ELSE 0 END
			) ivt
				OUTER APPLY (
					SELECT p.ProductId
					FROM @ChargeSetting p
						INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON p.ProductId = c.ProductId AND p.FromDate = c.FromDate
					WHERE c.FromParty = @PayerID AND c.ToParty = @ToParty
						AND ivt.InvTemplateName IN ('Boping', 'Zelianta')
						AND p.StatusId > 0
				) p
			WHERE p.ProductId IS NOT NULL -- @BillingGroupId <> 0 for when lauching licensees
				AND NOT EXISTS (
					SELECT 1 FROM dbo.LA_InvoiceSetting l WITH(NOLOCK) 
					WHERE l.FromPartyId = @PayerID 
						AND l.ToPartyId = @BillerId 
						AND (l.ProductId  = p.ProductId  OR (l.ProductId IS NULL AND p.ProductId IS NULL)) 
						AND l.InvTypeId = ivt.InvTypeId
				)
		
		SELECT @ChargeSettingXMLOUT = 
		(
				SELECT 
					ChargeId
					,ProductId
					,FirstBilling
					,BasisBilling
					,BettypeRef
					,Rate
					,ChargeType
					,FromDate
					,ToDate
					,IsChangedRate
					,IsChangedDate
				FROM @ChargeSetting	c	
				FOR XML PATH ('ChargeSetting'), ROOT('ChargeSettings'), TYPE
		)

		-- update system mapping
		INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
		SELECT ChargeID, 2 FROM @MergeResult WHERE [$action]='INSERT'

		IF @ToParty = 1 -- ONEWorks
		BEGIN
			INSERT INTO LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
			SELECT m.ChargeID, 4
			FROM @MergeResult m
			WHERE m.ProductId IN (SELECT p.ProductId FROM dbo.LRF_f_Products3rd('SB,NG,VS,LC,AGC,GD,VG,BA') p)
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

		-- Write Log
		EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@LicenseeID	= 0
			,@CurrencyID	= 0
			,@SPName		= 'LA_ChargeRateSettingModify'
			,@CustId		= 0
			,@Duration		= @duration
			,@Data			= @logSPData
			,@OldData		= @logSPDataOld
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