/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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

*/
BEGIN
	SET NOCOUNT ON
	
	-- Get Party List
	DECLARE @PartyList TABLE (PartyId INT, LicenseeCode VARCHAR(100))
	INSERT INTO @PartyList (PartyId)
	SELECT value FROM STRING_SPLIT(@PartyIds, ',')

	UPDATE p
	SET p.LicenseeCode = UPPER(ISNULL(bc.LicenseeCode, '') + '|' + CONVERT(VARCHAR(20), p.PartyId))
	FROM @PartyList p
		LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

	-- Get Product List
	DECLARE @ProductList TABLE (ProductId INT, ProductCode VARCHAR(50), ProductName VARCHAR(50))
	INSERT INTO @ProductList (ProductId, ProductCode, ProductName)
	SELECT ProductId, ProductPrefix, ProductName FROM dbo.Product3rd WITH (NOLOCK) WHERE ProductId <> 16 AND (EndOfSupportDate IS NULL OR EndOfSupportDate >= @FromDate) AND OfferSite IN (0, 2) -- Deposit only
	UNION ALL SELECT 0, 'SB', 'Sportsbook'

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM @ProductList

	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
	)
	INSERT INTO @Result
	(
		PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
		,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
	)
	EXEC dbo.LA_AmountToCompanyByProduct
		@PartyIds = @PartyIds
		,@ProductCodes = @ProductCodes
		,@FromDate = @FromDate
		,@ToDate = @ToDate
		,@LicensingFeeTypeIds = '0,7,8,9' -- 7 = ContributionDiscount, 8 = BetCount, 9 = OddsSpeadAdjustment
		,@BaseCurrencyName = @BaseCurrency

	DECLARE @FinalResult TABLE (PartyId INT, ProductId INT, AmountToCompany MONEY, LicensingFee MONEY, Discount MONEY, Rebate MONEY, Promotion MONEY, Sponsorship MONEY, ContributionDiscount MONEY, BetCount INT, OddsSpreadCost MONEY, PlayerTips MONEY)
	INSERT INTO @FinalResult (PartyId, ProductId, AmountToCompany, LicensingFee, Discount, Rebate, Promotion, Sponsorship, ContributionDiscount, BetCount, OddsSpreadCost, PlayerTips)
	SELECT r.PartyId, r.ProductId, r.GrossLicensingFee, r.LicensingFee + r.ExtraAmount, r.Discount, r.Rebate, ISNULL(t.Promotion, 0), ISNULL(t.Sponsorship, 0), ISNULL(t.ContributionDiscount, 0), ISNULL(t.BetCount, 0), ISNULL(t.OddsSpreadAdjustment, 0), ISNULL(t.PlayerTips,0)
	FROM @Result r
		LEFT JOIN (
			SELECT PartyId, CASE WHEN ProductId IN (37, 74) THEN 0 ELSE ProductId END AS ProductId
				,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN LicensingFee ELSE 0 END) AS Promotion
				,SUM(CASE WHEN ProductId = 37 AND LicensingFeeTypeId = 0 THEN ExtraAmount ELSE 0 END) AS Sponsorship
				,SUM(CASE WHEN LicensingFeeTypeId = 7 THEN ExtraAmount ELSE 0 END) AS ContributionDiscount
				,SUM(CASE WHEN LicensingFeeTypeId = 8 THEN ExtraAmount ELSE 0 END) AS BetCount
				,SUM(CASE WHEN LicensingFeeTypeId = 9 AND ExtraAmount < 0 THEN -ExtraAmount ELSE 0 END) AS OddsSpreadAdjustment
				,SUM(CASE WHEN ProductId = 74 AND LicensingFeeTypeId = 0 THEN ExtraAmount ELSE 0 END) AS PlayerTips
			FROM @Result
			WHERE ProductId IN (37,74) OR LicensingFeeTypeId > 0
			GROUP BY PartyId,CASE WHEN ProductId IN (37, 74) THEN 0 ELSE ProductId END
		) t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
	WHERE r.LicensingFeeTypeId = 0 AND r.ProductId NOT IN (37, 74)

	-- Return data
	IF @IsShowSettlementDetail = 1
	BEGIN
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
			FROM @FinalResult r
				INNER JOIN @PartyList p ON r.PartyId = p.PartyId
			GROUP BY p.LicenseeCode
	END
END
GO