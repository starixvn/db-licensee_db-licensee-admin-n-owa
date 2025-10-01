/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_AmountToCompanySel]
	@PartyIds					VARCHAR(MAX)
	,@FromDate					DATE
	,@ToDate					DATE
	,@BaseCurrency				VARCHAR(5)
	,@Environment				VARCHAR(50) = 'DEV'
	,@IsShowSettlementDetail	BIT = 0
	,@IsSyncProductWithInvoice	BIT = 0
	,@IsGroupByPartyId			BIT = 0
	,@PlatformId				TINYINT = 0
AS
/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
		- 20190927@Bruce: Remove prepayment section and Include CardClub [#120220]
		- 20191017@Bruce: Group by party id [#122229]
		- 20191209@Bruce: Include PP tournament [123958]
		- 20200117@Mason: Setup billing terms by Currency  [#120005]
		- 20200309@Parsons: Intergrate SpadeGaming [#123959]
		- 20200316@Parsons: Integrate Virtual Games [#125222]
		- 20200323@Parsons: Intergrate Indo 4D [#130910]
		- 20200412@Parsons: Integrate SA Gaming [#129276]
		- 20200411@Parsons: Integrate Table Games [#131166]
		- 20200422@Parsons: Integrate Saba.club [#132730]
		- 20200507@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
		- 20200528@Parsons: Special handling for INH market [#128570] 
		- 20200624@Parsons: Keep Negative Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334] 
		- 20200727@Parsons: Implement PP Jackpot [RedmineID: #137306] 
		- 20200813@Parsons: Implement Group Min Fee [#134492]
		- 20200909@Parsons: Implement PG Soft [RedmineID: #138983]
		- 20200930@Parsons: Implement Joker Games [RedmineID: #141421]
		- 20201104@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
	    - 20201118@Parsons: Changing OddsSpread for licensee [#142345]
	    - 20201217@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20201223@Happy: Implement WM [#141357]
		- 20201223@Parsons: Integrate Leap Gaming Virtual Sports [#145339]
		- 20201230@Parsons: Integrate Gold Diamond Gaming [#145340]
		- 20201231@Parsons: Integrate Big Gaming [#145342]
		- 20210106@Happy: Integrate MaxGame [#147375]
	    - 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210406@Parsons: Support duo base currency [RedmineID: #152089]
		- 20210407@Mason: Integrate new Sport Lottery [#150866]
		- 20210407@Percy: Support duo base currency - Change code for Collection Summary [RedmineID: #152089]
		- 20210506@Percy: Integrate
			. Pragmatic Live Casino [RedmineID: #150971]
			. Habanero [RedmineID: #150636]
			. Creative Gaming [RedmineID: #152139]
		- 20210513@Percy: Apply function to get Joint Venture Party List - Keep negative licensee fee [RedmineID: #154992]
		- 20210609@Danny: Support AE Sexy Promotion [RedmineID: #152089]
		- 20210306@Danny: Integrate VGaming [#154080]
		- 20210614@Danny: Integrate AdvantPlay [#154787]
		- 20210614@Danny: Integrate AdvantPlay Mini [#155207]
		- 20210705@Percy: Add ContributionDiscount column [RedmineID: #157549]
		- 20210720@Sophia: Add Saba Promotion - 17005 - Promotion for Licensee [Redmine: #155388]
		- 20210726@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210727@Percy: Return ProductId for Detail Mode [RedmineID: #155593]
		- 20210813@Percy: Remove check negative amount of ContributionDiscount [RedmineID: #159294]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211212@Percy: Return OddsSpreadCost for Detail Mode [RedmineID: #165849]
		- 20220218@Percy: Return BetCount [RedmineID: #161429]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20231005@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 [RedmineID: #194561]
		- 20230223@Danny: Integrate Casino promotion [#194808]
		- 20241014@Sally: Support Odds Boost Voucher [#209884]
		- 20241225@Danny: Fix Casino promotion Rebate issue [#209884]
		- 20250421@Danny: Support billing SabaPlay licensees [RedmineID: #217742]
		- 20251001@Danny: Balance Carry Forward setting [RedmineID: #225392]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FinalResult TABLE (PartyId INT, ProductId INT, AmountToCompany MONEY, LicensingFee MONEY, Discount MONEY, Rebate MONEY, Promotion MONEY, Sponsorship MONEY, ContributionDiscount MONEY, BetCount INT, OddsSpreadCost MONEY, PlayerTips MONEY, OddsBoostBonus MONEY, SabaPlay MONEY)

	-- Get Party List
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		IF @PlatformId <> 99
		BEGIN
			SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
			FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
				INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
				INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
			WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ','))  
		END
		ELSE
		BEGIN
			SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
			FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ','))  AND @PlatformId = 99 AND p.PlatformId = 2
		END
	END

	DECLARE @PartyList TABLE (PartyId INT, LicenseeCode VARCHAR(100), PlatformId SMALLINT)
	INSERT INTO @PartyList (PartyId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')

	UPDATE p
	SET p.LicenseeCode = UPPER(ISNULL(bc.LicenseeCode, '') + '|' + CONVERT(VARCHAR(20), p.PartyId)),
		p.PlatformId = op.PlatformId
	FROM @PartyList p
	INNER JOIN dbo.OAS_Party op WITH(NOLOCK) ON p.PartyId = op.PartyID
		LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate


	DECLARE @PartyIds_SabaSports VARCHAR(MAX), @PartyIds_SabaPlay VARCHAR(MAX)

	SELECT @PartyIds_SabaSports = STRING_AGG(CONVERT(VARCHAR(50), p.PartyID),',')
	FROM @PartyList p
	WHERE PlatformId <> 2

	SELECT @PartyIds_SabaPlay = STRING_AGG(CONVERT(VARCHAR(50), p.PartyID),',')
	FROM @PartyList p
	WHERE PlatformId = 2

	IF @PartyIds_SabaSports IS NOT NULL
	BEGIN
		-- Get Product List
		DECLARE @ProductList TABLE (ProductId INT, ProductCode VARCHAR(50), ProductName VARCHAR(50))
		INSERT INTO @ProductList (ProductId, ProductCode, ProductName)
		SELECT ProductId, ProductPrefix, ProductName FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId <> 16 AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
		UNION ALL SELECT 0, 'SB', 'Sportsbook'
		UNION ALL SELECT 1003,'OddsBoost', 'Odds Boost Bonus'

		DECLARE @ProductCodes VARCHAR(MAX)
		SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM @ProductList

		SELECT @ProductCodes = @ProductCodes +',SPR(CS)'

		DECLARE @PartyIds_AlekGroup VARCHAR(200), @isRecalRebate BIT = 0, @RecalRebateEffectiveFrom DATETIME , @RecalRebateEffectiveTo DATETIME
	
		SELECT @PartyIds_AlekGroup = STRING_AGG(CONVERT(VARCHAR(50), op.PartyID), ',')
		FROM bodb_licensee.dbo.OAS_Party op WITH(NOLOCK)
		INNER JOIN (
			SELECT CAST(value AS INT ) AS PartyID FROM STRING_SPLIT(@PartyIds, ',')
		) x ON op.PartyID = x.PartyID
		WHERE op.PartyName IN ('BigGaming','HuangMa','BGCV','VNS888')

		IF @PartyIds_AlekGroup IS NOT NULL
			SELECT @isRecalRebate = 1

		IF @isRecalRebate = 1
		SELECT @RecalRebateEffectiveFrom = '2023-10-01', @RecalRebateEffectiveTo = '2024-09-01'

		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), ExtraInfo NVARCHAR(4000)
		)
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@LicensingFeeTypeIds = '0,7,8,9,13,14' -- 7 = ContributionDiscount, 8 = BetCount, 9 = OddsSpeadAdjustment, 14 = Odds Boost Adjustment
			,@BaseCurrencyName = @BaseCurrency

		IF @isRecalRebate =1 AND @FromDate BETWEEN @RecalRebateEffectiveFrom AND @RecalRebateEffectiveTo AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SB')
		BEGIN
			DECLARE @Result_OldSetting TABLE
			(
				PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
				,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
				,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
			)
			INSERT INTO @Result_OldSetting
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds_AlekGroup
				,@ProductCodes = 'SB'
				,@FromDate = @FromDate
				,@ToDate = @ToDate
				,@BaseCurrencyName = @BaseCurrency
				,@IsUsePreviousSetting = 1

			IF EXISTS (SELECT TOP 1 1 FROM @Result_OldSetting) 
			BEGIN
				UPDATE r
				SET r.Rebate = ri.Rebate
				FROM @Result r
				INNER JOIN @Result_OldSetting ri ON r.PartyId = ri.PartyId AND r.ProductId = ri.ProductId AND ri.LicensingFeeTypeId = 0
				WHERE r.LicensingFeeTypeId = 0 AND r.PartyId IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds_AlekGroup,','))
				 
				DELETE FROM @Result_OldSetting
			END
		END

		INSERT INTO @FinalResult (PartyId, ProductId, AmountToCompany, LicensingFee, Discount, Rebate, Promotion, Sponsorship, ContributionDiscount, BetCount, OddsSpreadCost, PlayerTips, OddsBoostBonus)
		SELECT r.PartyId, r.ProductId, r.GrossLicensingFee, r.LicensingFee + r.ExtraAmount, r.Discount, r.Rebate + ISNULL(t.CasinoPromotionRebate,0), ISNULL(t.Promotion, 0), ISNULL(t.Sponsorship, 0), ISNULL(t.ContributionDiscount, 0), ISNULL(t.BetCount, 0), ISNULL(t.OddsSpreadAdjustment, 0), ISNULL(t.PlayerTips,0), ISNULL(t.OddsBoostBonus,0)
		FROM @Result r
			LEFT JOIN (
				SELECT PartyId, CASE WHEN ProductId IN (37, 74, -37) THEN 0 ELSE ProductId END AS ProductId
					,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN LicensingFee 
							  WHEN LicensingFeeTypeId = 13 THEN ExtraAmount ELSE 0 END) AS Promotion
					,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN ExtraAmount ELSE 0 END) AS Sponsorship
					,SUM(CASE WHEN LicensingFeeTypeId = 7 THEN ExtraAmount ELSE 0 END) AS ContributionDiscount
					,SUM(CASE WHEN LicensingFeeTypeId = 8 THEN ExtraAmount ELSE 0 END) AS BetCount
					,SUM(CASE WHEN LicensingFeeTypeId = 9 AND ExtraAmount < 0 THEN -ExtraAmount ELSE 0 END) AS OddsSpreadAdjustment
					,SUM(CASE WHEN ProductId = 74 AND LicensingFeeTypeId = 0 THEN -ExtraAmount ELSE 0 END) AS PlayerTips -- Recon Show Negative value
					,SUM(CASE WHEN ProductId = -37 AND LicensingFeeTypeId = 13 THEN Rebate ELSE 0 END) AS CasinoPromotionRebate
					,SUM(CASE WHEN ProductId = 0 AND LicensingFeeTypeId = 14 THEN ExtraAmount ELSE 0 END) AS OddsBoostBonus
				FROM @Result
				WHERE ProductId IN (37,74) OR LicensingFeeTypeId > 0
				GROUP BY PartyId,CASE WHEN ProductId IN (37, 74, -37) THEN 0 ELSE ProductId END
			) t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
		WHERE r.LicensingFeeTypeId = 0 AND r.ProductId NOT IN (37, 74, -37)

	END

	IF @PartyIds_SabaPlay IS NOT NULL
	BEGIN
		DECLARE @SabaPlay_@ProductIDs VARCHAR(MAX)

		SElECT @SabaPlay_@ProductIDs =  STRING_AGG(CONVERT(VARCHAR(50), ProductID),',')
		FROM bodb_licenseeReport.dbo.SabaPlay_Products WITH(NOLOCK)
		
		DECLARE  @SabaPlay_Result TABLE (PartyId INT, ProductId INT,LicensingFee MONEY,Discount MONEY)
		INSERT INTO @SabaPlay_Result(PartyId, ProductId, LicensingFee, Discount)
		EXEC dbo.SH_SabaPLay_AmountToCompanyByProduct
			@PartyIds = @PartyIds_SabaPlay
			,@ProductIDs = @SabaPlay_@ProductIDs
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrency
			,@Environment	= @Environment


		UPDATE r
		SET r.LicensingFee = 0
		FROM @SabaPlay_Result r 
		INNER JOIN DBCUST.bodb_licensee.dbo.SH_SabaPlay_BalanceCarryForwardSetting p WITH(NOLOCK)  ON r.PartyId = p.PartyId 
		WHERE p.IsBalanceCarryForward = 0 AND r.LicensingFee < 0 

		INSERT INTO @FinalResult (PartyId, ProductId, SabaPlay)
		SELECT PartyId, ProductId, LicensingFee
		FROM @SabaPlay_Result
	END

	-- Return data
	IF @IsShowSettlementDetail = 1
	BEGIN
		-- Get data Odds Boost Bonus
		INSERT INTO @FinalResult(PartyId, ProductId, AmountToCompany)
		SELECT PartyId, 1003 AS ProductId, -SUM(ISNULL(OddsBoostBonus,0)) AS AmountToCompany
		FROM @FinalResult
		WHERE ProductId = 0
		GROUP BY PartyId
		HAVING SUM(ISNULL(AmountToCompany,0)) <> 0

		IF @IsGroupByPartyId = 1
			SELECT r.PartyId, p.ProductName, p.ProductId, UPPER(@BaseCurrency) AS CurrencyName, SUM(r.AmountToCompany) AS AmountToCompany
			FROM @FinalResult r
				INNER JOIN @ProductList p ON r.ProductId = p.ProductId
			GROUP BY r.PartyId, p.ProductName, p.ProductId
		ELSE
			SELECT pl.LicenseeCode, p.ProductName, p.ProductId, UPPER(@BaseCurrency) AS CurrencyName, SUM(r.AmountToCompany) AS AmountToCompany
			FROM @FinalResult r
				INNER JOIN @ProductList p ON r.ProductId = p.ProductId
				INNER JOIN @PartyList pl ON r.PartyId = pl.PartyId
			GROUP BY pl.LicenseeCode, p.ProductId, p.ProductName
			ORDER BY p.ProductId
	END
	ELSE
	BEGIN
		IF @IsGroupByPartyId = 1
			SELECT r.PartyId
				,UPPER(@BaseCurrency)			AS CurrencyName
				,SUM(r.AmountToCompany)			AS AmountToCompany
				,SUM(r.LicensingFee)			AS LicensingFee
				,SUM(r.Discount)				AS Discount
				,SUM(r.Rebate)					AS Rebate
				,SUM(r.Promotion)				AS Promotion
				,SUM(r.Sponsorship)				AS Sponsorship
				,SUM(r.PlayerTips)				AS PlayerTips
				,SUM(r.ContributionDiscount)	AS ContributionDiscount
				,SUM(r.OddsSpreadCost)			AS OddsSpreadCost
				,SUM(r.BetCount)				AS BetCount
				,SUM(r.OddsBoostBonus)			AS OddsBoostBonus
				,SUM(r.SabaPlay)				AS SabaPlay
			FROM @FinalResult r
			GROUP BY r.PartyId
		ELSE
			SELECT p.LicenseeCode
				,UPPER(@BaseCurrency)			AS CurrencyName
				,SUM(r.AmountToCompany)			AS AmountToCompany
				,SUM(r.LicensingFee)			AS LicensingFee
				,SUM(r.Discount)				AS Discount
				,SUM(r.Rebate)					AS Rebate
				,SUM(r.Promotion)				AS Promotion
				,SUM(r.Sponsorship)				AS Sponsorship
				,SUM(r.PlayerTips)				AS PlayerTips
				,SUM(r.ContributionDiscount)	AS ContributionDiscount
				,SUM(r.OddsSpreadCost)			AS OddsSpreadCost
				,SUM(r.BetCount)				AS BetCount
				,SUM(r.OddsBoostBonus)			AS OddsBoostBonus
				,SUM(r.SabaPlay)				AS SabaPlay
			FROM @FinalResult r
				INNER JOIN @PartyList p ON r.PartyId = p.PartyId
			GROUP BY p.LicenseeCode
	END
END
GO