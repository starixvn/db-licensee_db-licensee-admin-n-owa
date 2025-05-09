/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
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
		- 20230213@Malcolm: Fix duplicate data error [RemineID: #183774]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
		- 20231002@Danny: logging currency information with new format [#FeatureID 193214]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
		- 20250429@Danny: Internal Template for OW Billing

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
									<ChargeTypeName>Licensing Fee</ChargeTypeName>
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
									<ChargeTypeName>Licensing Fee</ChargeTypeName>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
								  </ChargeSetting>
								</ChargeSettings>'
								
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML, @ChargeSettingsXML XML, @LicenseeID INT,
			@LogActionID INT = 1200
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
		ChargeTypeName	NVARCHAR(MAX),
		FromDate		DATE,
		ToDate			DATE,
		StatusId		TINYINT,
		IsChangedRate	BIT DEFAULT(1),
		IsChangedDate	BIT DEFAULT(0)
	)

	DECLARE @ChargeRate AS TABLE (ChargeID INT, ProductId INT, BettypeRef INT, FromDate DATE, ToDate DATE)

	INSERT INTO @ChargeSetting (ChargeID ,ProductId ,FirstBilling, BasisBilling, BettypeRef, Rate, ChargeType, ChargeTypeName, FromDate, ToDate, StatusId)
	SELECT	t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeID,
			t.c.value('(ProductId/text())[1]', 'INT') AS ProductId,
			t.c.value('(FirstBilling/text())[1]', 'DATE') AS FirstBilling,
			t.c.value('(BasisBilling/text())[1]', 'NVARCHAR(MAX)') AS BasisBilling,
			t.c.value('(BettypeRef/text())[1]', 'INT') AS BettypeRef,
			t.c.value('(Rate/text())[1]', 'MONEY') AS Rate,			
			t.c.value('(ChargeType/text())[1]', 'INT') AS ChargeType,	
			t.c.value('(ChargeTypeName/text())[1]', 'NVARCHAR(MAX)') AS ChargeTypeName,
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

	-- Empty
	DECLARE @cnt INT
	SELECT @cnt = COUNT(1) FROM @ChargeSetting

	IF @cnt = 0 
		RETURN

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
		-- Old data
		IF EXISTS (SELECT TOP 1 1 FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ChargeID IN (SELECT z.ChargeID FROM @ChargeSetting z))
		BEGIN
			SELECT @LogActionID = 1201
			;WITH t AS
			(
				SELECT		op.PartyName,
							od.BrandName,
						   CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
						   FORMAT (oc.FromDate,'MMM dd, yyyy') FromDate,
						   FORMAT (oc.ToDate,'MMM dd, yyyy') ToDate,
						   FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') FirstOfBilling,
						   oc.BasisOfBilling,
						   CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END Rate,
						   STRING_AGG(x.Code,', ') Currs,
						   CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate,
						   oc.ChargeID AS FakeID,
						   z.ChargeTypeName
				FROM OAS_Party op WITH(NOLOCK)
				INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
				INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
				INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty
				CROSS APPLY (
					SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId = 142 THEN 'USDT' WHEN e.ExchangeId IN (96,202,206,208,209) THEN  e.Code + ' (' + e.currency + ')'  ELSE e.Code END Code
					FROM LicenseeCust lc  WITH(NOLOCK) 
					INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
					WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
				) x
				INNER JOIN @ChargeSetting z ON z.ChargeID = oc.ChargeID
				LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
				LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
				WHERE op.PartyID = @PayerID 
				GROUP BY op.PartyName,
							od.BrandName,
							CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
							FORMAT (oc.FromDate,'MMM dd, yyyy') ,
						    FORMAT (oc.ToDate,'MMM dd, yyyy') ,
						    FORMAT (oc.FirstOfBilling,'MMM dd, yyyy'),
							oc.BasisOfBilling,
							CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END,
							CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END,
							oc.ChargeID,
							z.ChargeTypeName
			) 
			, t1 AS
			(
				SELECT t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName,STRING_AGG(cr.r, CHAR(13)) AS r
				FROM t
				CROSS APPLY (
						SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
									WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
									ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
				) cr
				GROUP BY t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName
			) SELECT @logSPDataOld = 
				 (
					SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
					FROM t1 t 
					CROSS APPLY 
					(
						SELECT 
						(
							SELECT  u.FakeID ,u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r, u.ChargeTypeName t
							FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
						) crs
					) crs  
					GROUP BY t.PartyName, t.BrandName, crs.crs
					FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
				) 
		END

		DECLARE @MergeResult TABLE(ChargeId INT, ProductId INT, [$action] VARCHAR(20))
		DECLARE @ToParty INT, @ParentChargeID INT, @Remark VARCHAR(200) = ''
		
		SELECT TOP 1 @ToParty = c.ToParty, @ParentChargeID = c.ParentChargeID
		FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
			INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON c.ChargeID = cs.ChargeID AND cs.SystemID = 2
		WHERE FromParty = @PayerID AND c.ToParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
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
							WHEN 'JollySports' THEN @BillingGroupName
							WHEN 'Zelianta' THEN @BillingGroupName + ' Limited'
							WHEN 'Double S' THEN @BillingGroupName
							WHEN 'ONEWorks' THEN 'Internal Settlement'
							ELSE '' END

		IF ISNULL(@BillerId, 0) <> 0
			INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
			SELECT DISTINCT @PayerID, @BillerId, ProductId, InvTypeId, InvTemplateId, 0 AS BankId, 1 AS ActiveAddress
			FROM (
				SELECT InvTemplateId, InvTemplateName
					,CASE InvTemplateName
						WHEN @BillingGroupName THEN 1 -- Software Data & Licensing Fees
						WHEN 'Double-S' THEN 1
						WHEN 'Internal-Settlement' THEN 1
						WHEN 'Credit' + CASE WHEN @BillingGroupName = 'JollySports' THEN '-JollySports' ELSE '' END THEN 4 -- Credit Note
						WHEN 'Credit' + CASE WHEN @BillingGroupName = 'Double S' THEN '-Double-S' ELSE '' END THEN 4 -- Credit Note
						WHEN 'Credit' + CASE WHEN @BillingGroupName = 'ONEWorks' THEN '-Internal-Settlement' ELSE '' END THEN 4 -- Credit Note
						ELSE 5 -- Debit Note
					END AS InvTypeId
				FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
				WHERE 1 = CASE InvTemplateName
							WHEN @BillingGroupName THEN 1
							WHEN CASE WHEN @BillingGroupName = 'Double S' THEN 'Double-S' ELSE '' END THEN 1
							WHEN CASE WHEN @BillingGroupName = 'ONEWorks' THEN 'Internal-Settlement' ELSE '' END THEN 1
							WHEN 'Credit'+ CASE WHEN @BillingGroupName = 'JollySports' THEN '-JollySports'
												WHEN @BillingGroupName = 'Double S' THEN '-Double-S'
												WHEN @BillingGroupName = 'ONEWorks' THEN '-Internal-Settlement' ELSE '' END THEN 1
							WHEN 'Debit' + CASE WHEN @BillingGroupName = 'Zelianta' THEN '-Zelianta' 
												WHEN @BillingGroupName = 'JollySports' THEN '-JollySports'
												WHEN @BillingGroupName = 'Double S' THEN '-Double-S'
												WHEN @BillingGroupName = 'ONEWorks' THEN '-Internal-Settlement'
												ELSE '' END THEN 1
							ELSE 0 END
					AND InvTemplateName <> 'ONEWorks'
			) ivt
				OUTER APPLY (
					SELECT p.ProductId
					FROM @ChargeSetting p
						INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON p.ProductId = c.ProductId AND p.FromDate = c.FromDate
					WHERE c.FromParty = @PayerID AND c.ToParty = @ToParty
						AND ivt.InvTemplateName IN ('Boping', 'Zelianta', 'JollySports','Double-S','Internal-Settlement')
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

		-- New log
		;WITH t AS
		(
			SELECT		op.PartyName,
						od.BrandName,
					   CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
					   FORMAT (oc.FromDate,'MMM dd, yyyy') FromDate,
					   FORMAT (oc.ToDate,'MMM dd, yyyy') ToDate,
					   FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') FirstOfBilling,
					   oc.BasisOfBilling,
					   CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END Rate,
					   STRING_AGG(x.Code,', ') Currs,
					   CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate,
					   oc.ChargeID AS FakeID,
					   z.ChargeTypeName
			FROM OAS_Party op WITH(NOLOCK)
			INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
			INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
			INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty
			CROSS APPLY (
				SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId = 142 THEN 'USDT' WHEN e.ExchangeId IN (96,202,206,208,209) THEN  e.Code + ' (' + e.currency + ')'  ELSE e.Code END Code
				FROM LicenseeCust lc  WITH(NOLOCK) 
				INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
				WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			) x
			INNER JOIN @ChargeSetting z ON z.ChargeID = oc.ChargeID
			LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
			LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
			WHERE op.PartyID = @PayerID 
			GROUP BY op.PartyName,
						od.BrandName,
						CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
						FORMAT (oc.FromDate,'MMM dd, yyyy') ,
						FORMAT (oc.ToDate,'MMM dd, yyyy') ,
						FORMAT (oc.FirstOfBilling,'MMM dd, yyyy'),
						oc.BasisOfBilling,
						CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END,
						CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END,
						oc.ChargeID,
						z.ChargeTypeName
		) 
		, t1 AS
		(
			SELECT t.FakeID ,t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName,STRING_AGG(cr.r, CHAR(13)) AS r
			FROM t
			CROSS APPLY (
					SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
								WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
								ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
			) cr
			GROUP BY t.FakeID, t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,t.ChargeTypeName
		) SELECT @logSPData = 
			 (
				SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
				FROM t1 t 
				CROSS APPLY 
				(
					SELECT 
					(
						SELECT  u.FakeID, u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r, u.ChargeTypeName t
						FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
					) crs
				) crs  
				GROUP BY t.PartyName, t.BrandName, crs.crs
				FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
			)
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

		-- Write Log
		EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
			@UserId			= @UserID
			,@IP			= @LoginIP
			,@SPName		= 'LA_ChargeRateSettingModify'
			,@CustId		= @PayerID
			,@Duration		= @duration
			,@TrackingValue2 = @logSPData
			,@TrackingValue = @logSPDataOld
			,@ActionID		 = @LogActionID
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