/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Detail]
	@PartyIds			 VARCHAR(MAX) = ''
	,@Currency			 INT = 0
	,@FromDate			 DATETIME
	,@ToDate			 DATETIME
	,@ProductCodes		 VARCHAR(MAX)
	,@IsConvert			 BIT = 1
	,@BaseCurrency		 INT = 6
	,@BaseCurrencyName	 VARCHAR(10) = 'EUR'
	,@DrawFilter		 SMALLINT = 1
	,@LicenseePaying	 INT = 0
	,@PreviousPeriodType INT = 1
	,@LicenseeStatusIds	 VARCHAR(100) 
	,@PlatformId		 TINYINT = 0
AS

/*	Created: 20141209@Patrick
	Task: LicenseeAdmin - Get Licensee Performance Detail report
	DB: DB052.bodb02

	Revisions:
		- 20150806@Florent: add column SB launch date to output
		- 20150814@Florent: add "*" on licensee name when pay minfee
		- 20151209@Bravo:	Enhance view data as billing invoice - re-write sp call data from table rpt_BettingByProduct
		- 20160128@Bruce: Fixbug:
					+ There is no minimum fee when data display individual currency
					+ Exclude Reject , Void, Refund
					+ Include other products
					+ LaunchDate = MIN(FromDate) of all charge types/products
					+ Convert Minfee currency
		- 20160202@Bruce: Add BA Commission and Amount due to BA
		- 20160608@Bruce: Fixbug:
					+ Fix credit licensees name
					+ Wrong data of credit licensee
					+ fix minfee amount when select single licensee in minfee group
		- 20161024@Scofield: 
					+ Calculate Discount for HAIFA (discount group type: 3)
					+ Fix minfee bug for case no ticket data
		- 20170412: @Scofield - Removing Trading Bet Types [#73310]
		- 20170830@Scofield: Rebate/ add more products for Licensee performance in details report[#80796]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20182501@Bruce: Include exchange winloss [#87754]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
		- 20180712@Bruce: Enhance Manage Discount group [#94282]
		- 20180718@Bruce: use decimal to void margin not match among reports [#94108]
		- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
		- 20180924@Parsons: LA - LPID report - Apply one discount rate across all base currencies [#100046]
		- 20181122@Scofield: Integrate Bidme games (GD product) [#103695]
	    - 20190325@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20190718@Bruce: Integrate CN88 data in LA [#116859]
		- 20191021@Parsons: Non-peak hour promotion [#119538]    
		- 20191125@Mason: Setup billing terms by Currency  [#120005]
	    - 20191205@Parsons: PP tournament [#123958]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
	    - 20200605@Parsons: Get Full Data For Licensee Groups [#135452]
		- 20200609@Parsons: Special handling for INH market [#128570] 
		- 20200624@Parsons: Keep Negative Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334]
		- 20200813@Parsons: Implement Group Min Fee [#134492]
	    - 20200821@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	    - 20200828@Parsons: Provide data of "this month last year" [#136417] 
		- 20200910@Parsons: Implement PP JP for Credit [#138984]
		- 20201007@Parsons: Always show party row regardless of having data or not [#142970]
		- 20201027@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
		- 20201209@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20210206@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210513@Percy: Apply function to get Joint Venture Party List - Keep negative licensee fee [RedmineID: #154992]
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]
		- 20210720@Sophia: Add Saba Promotion - 17005 - Promotion for Licensee [Redmine: #155388]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210929@Percy: Enhance performance - work around [RedmineID: #162390]
		- 20211005@Percy: Get date only for Previous Date [RedmineID: #162753]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211216@Percy: Enhance performance - Change table variable to temp table [RedmineID: #163181]
		- 20210824@Danny: filter licensee status from OIC [#159296]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20231005@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 [RedmineID: #194561]
		- 20230223@Danny: Integrate Casino promotion [#194808]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]

	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @ProductCode : string,

	  + @IsConvert: =1 : convert figure to
					=0 : no convert 
					(datatype:bit)
	  + @BaseCurrency /  @BaseCurrencyName
					6 : convert to EUR
					 2: convert to MYR
					 3: convert to USD
					 12: convert to GBP
					 13: convert to CNY
	  + @LicenseePaying: =0 : All
					=1 : Normal fee 
					=2 : Minimum fee
					=3 : Group min fee 
	  + @PreviousPeriodType: = 1: Same month last year
	                         = 2: Last month
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATETIME = @FromDate, @TDate DATETIME = @ToDate
	DECLARE @PrevFDate DATETIME, @PrevTDate DATETIME

	SELECT @PrevFDate = CASE WHEN @PreviousPeriodType = 1 THEN DATEADD(YEAR, -1, @FDate) ELSE DATEADD(MONTH, -1, @FDate) END
	SELECT @PrevTDate = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @PrevFDate) + 1, 0))

	IF DAY(@PrevTDate) > DAY(@TDate) AND @TDate <> DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @TDate) + 1, 0))
		SELECT @PrevTDate = CONVERT(VARCHAR(8), @PrevTDate, 120) + CONVERT(VARCHAR(2), @TDate, 103)

	DECLARE @statusTab TABLE (StatusId INT)
	INSERT INTO @statusTab (StatusId)
	SELECT CAST (value AS INT) FROM STRING_SPLIT(@LicenseeStatusIds,',')

	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId TINYINT)
	INSERT INTO #tmp_licenseeOIC(RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK)

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


	-- Get Party List
	BEGIN
		IF ISNULL(@PlatformId, 0) <> 0
		BEGIN
			SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
			FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
				INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
			WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
		END

		DECLARE @PartyList TABLE (PartyId INT, PartyName VARCHAR(50), LaunchDate DATE, StatusID INT)
		INSERT INTO @PartyList (PartyId)
		SELECT DISTINCT value FROM STRING_SPLIT(@PartyIds, ',')

		UPDATE pl
		SET pl.PartyName = CASE p.PartyName
								WHEN '18bb' THEN 'PIH'
								WHEN 'IBC' THEN 'FDL'
								ELSE p.PartyName END
			,pl.LaunchDate = c.LaunchDate
		FROM @PartyList pl
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId AND p.PartyType = 1
			OUTER APPLY (
				SELECT TOP 1 c.FromDate AS LaunchDate
				FROM bodb_Licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK)
				WHERE pl.PartyId = c.FromParty
					AND c.ChargeType NOT IN (2, 3) -- old type
					AND c.ToParty IN (SELECT z.PartyID FROM bodb_licensee.dbo.LA_f_BillingGroupSel() z ) -- licensee to house
				ORDER BY c.FromDate
			) c
		

		UPDATE p
		SET p.StatusId = CASE	WHEN la.IsDeposit = 0 THEN 3 -- Active (Credit)
								WHEN la.IsDeposit = 1 AND oic.LicenseeStatusId IS NULL THEN 999 -- 999: Unrecognized dummy status
								ELSE oic.LicenseeStatusId END 
		FROM  @PartyList p
			INNER JOIN bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) ON op.PartyID = p.PartyID
			INNER JOIN bodb_licensee.dbo.Licensees la WITH (NOLOCK) ON la.LicenseeId = op.OldRefID
			LEFT JOIN  #tmp_licenseeOIC oic WITH (NOLOCK) ON oic.RegisteredLicenseeName = la.LicenseeName

		DELETE  @PartyList 
		WHERE StatusID NOT IN (SELECT x.StatusId FROM @statusTab x) 

		SET @PartyIds = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyList FOR XML PATH(''))

		DELETE @PartyList WHERE PartyName IS NULL
	END

	-- Get TO/WL/LicensingFee Data
	BEGIN
		DECLARE @Currencies VARCHAR(MAX) = CASE WHEN ISNULL(@Currency, 0) = 0 THEN '' ELSE CONVERT(VARCHAR(20), @Currency) END

		DECLARE @Exchange TABLE (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
		CREATE TABLE #_tmp_PartyChargeInfo (PartyId INT, LicenseeId INT, ProductId INT, FromDate DATETIME, ToDate DATETIME)
		CREATE TABLE #PerformanceData
		(
			rptDate DATE, LicenseeId INT, PartyId INT, ProductId INT, CurrencyId INT
			,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY
		)
		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
			,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
		)

		-- From/To
		INSERT INTO @Exchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, CASE WHEN @IsConvert = 1 THEN BaseCurrencyRate ELSE 1 END
		FROM dbo.LA_f_ExchangeDailySel(@FDate, @TDate, @BaseCurrencyName)

		INSERT INTO #_tmp_PartyChargeInfo (PartyId, LicenseeId, ProductId, FromDate, ToDate)
		SELECT DISTINCT PartyId, LicenseeId, ProductId, FromDate, ToDate
		FROM bodb_Licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FDate, @TDate, @ProductCodes)

		DECLARE @Products TABLE (GroupProductId INT, ProductId INT, FromDate DATE, ToDate DATE)
		INSERT INTO @Products (GroupProductId, ProductId, FromDate, ToDate)
		SELECT GroupProductId, ProductId, FromDate, ToDate FROM bodb_licensee.dbo.LA_f_GroupProduct(@ProductCodes,@FDate,@TDate) 

		;WITH CTE_PerformanceData AS (
			SELECT r.rptDate, r.SiteId, gp.GroupProductId AS ProductId, r.CurrencyId
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.BetCount END) AS BetCount
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.Turnover END) AS Turnover
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.MemberWL + r.CommissionP END) AS MemberWL
				,SUM(CommissionA) AS BACommission
			FROM (
				SELECT rptDate, SiteId, ProductId, CurrencyId, Bettype
					,SUM(BetCount * CASE
										WHEN ISNULL(TicketType, 0) = 2 THEN 0
										WHEN @DrawFilter = 2 AND StatusId = 111 THEN 0
										ELSE 1 END) AS BetCount
					,SUM(Turnover * CASE
										WHEN ISNULL(TicketType, 0) = 2 THEN 0
										WHEN @DrawFilter NOT IN (2, 3) THEN 1
										WHEN StatusId = 111 THEN 0
										WHEN StatusId IN (114, 115) THEN 0.5
										ELSE 1 END) AS Turnover
					,SUM(CASE WHEN ISNULL(TicketType, 0) = 2 THEN 0 ELSE MemberWL END) AS MemberWL
					,SUM(CASE WHEN ProductId = 31 THEN CommissionP ELSE 0 END) AS CommissionP
					,SUM(CASE WHEN ProductId = 3 THEN CommissionA ELSE 0 END) AS CommissionA
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
				WHERE rptDate BETWEEN @FDate AND @TDate
					AND CurrencyId <> 20
					AND CustomerCategory NOT IN (27, 28)
					AND StatusId IN (111, 112, 113, 114, 115)
					AND (@Currency = 0 OR CurrencyId = @Currency)
				GROUP BY rptDate, SiteId, ProductId, CurrencyId, Bettype
				UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL -- sum data first
			) r
				INNER JOIN @Products gp ON r.ProductId = gp.ProductId AND r.rptDate BETWEEN gp.FromDate AND gp.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() gb ON r.Bettype = gb.Bettype
			GROUP BY r.rptDate, r.SiteId, gp.GroupProductId, r.CurrencyId
		)
		INSERT INTO #PerformanceData (rptDate, LicenseeId, PartyId, ProductId, CurrencyId, BetCount, Turnover, MemberWL, BACommission)
		SELECT d.rptDate, d.SiteId, p.PartyId, d.ProductId, d.CurrencyId, SUM(d.BetCount), SUM(d.Turnover), SUM(d.MemberWL), SUM(d.BACommission)
		FROM CTE_PerformanceData d
			INNER JOIN #_tmp_PartyChargeInfo p ON d.SiteId = p.LicenseeId AND d.ProductId = p.ProductId AND d.rptDate BETWEEN p.FromDate AND p.ToDate
		GROUP BY d.rptDate, d.SiteId, p.PartyId, d.ProductId, d.CurrencyId

		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@Currencies = @Currencies
			,@FromDate = @FDate
			,@ToDate = @TDate
			,@IsConvertExRate = @IsConvert
			,@BaseCurrencyName = @BaseCurrencyName
			,@LicensingFeeTypeIds = '0,13'

		IF @isRecalRebate =1 AND @FDate BETWEEN @RecalRebateEffectiveFrom AND @RecalRebateEffectiveTo AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SB')
		BEGIN
			DECLARE @Result_InMonth TABLE
			(
				PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
				,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
				,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
			)
			INSERT INTO @Result_InMonth
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds_AlekGroup
				,@ProductCodes = 'SB'
				,@Currencies = @Currencies
				,@FromDate = @FDate
				,@ToDate = @TDate
				,@IsConvertExRate = @IsConvert
				,@BaseCurrencyName = @BaseCurrencyName
				,@IsUsePreviousSetting = 1


			IF EXISTS (SELECT TOP 1 1 FROM @Result_InMonth) 
			BEGIN
				UPDATE r
				SET r.Rebate = ri.Rebate
				FROM @Result r
				INNER JOIN @Result_InMonth ri ON r.PartyId = ri.PartyId AND r.ProductId = ri.ProductId AND ri.LicensingFeeTypeId = 0
				WHERE r.LicensingFeeTypeId = 0 AND r.PartyId IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds_AlekGroup,','))
				 
				DELETE FROM @Result_InMonth
			END
		END

		UPDATE r
		SET r.IsPrevious = 0
			,r.LicensingFee = r.LicensingFee + CASE WHEN r.ProductId = 37 THEN 0 ELSE r.ExtraAmount END
			,r.BetCount = d.BetCount, r.Turnover = d.Turnover, r.MemberWL = d.MemberWL
			,r.BACommission = d.BACommission
		FROM @Result r
			LEFT JOIN (
				SELECT p.PartyId, p.ProductId
					,SUM(p.BetCount) AS BetCount
					,SUM(p.Turnover * e.Rate) AS Turnover
					,SUM(p.MemberWL * e.Rate) AS MemberWL
					,SUM(p.BACommission * e.Rate) AS BACommission
				FROM #PerformanceData p
					INNER JOIN @Exchange e ON p.CurrencyId = e.ExchangeId AND p.rptDate = e.ExchangeDate
				GROUP BY p.PartyId, p.ProductId
			) d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId

		-- Previous From/To
		DELETE @Exchange
		DELETE #_tmp_PartyChargeInfo
		DELETE #PerformanceData

		INSERT INTO @Exchange (ExchangeDate, ExchangeId, Rate)
		SELECT ExchangeDate, ExchangeId, CASE WHEN @IsConvert = 1 THEN BaseCurrencyRate ELSE 1 END
		FROM dbo.LA_f_ExchangeDailySel(@PrevFDate, @PrevTDate, @BaseCurrencyName)

		INSERT INTO #_tmp_PartyChargeInfo (PartyId, LicenseeId, ProductId, FromDate, ToDate)
		SELECT DISTINCT PartyId, LicenseeId, ProductId, FromDate, ToDate
		FROM bodb_Licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @PrevFDate, @PrevTDate, @ProductCodes)

		DECLARE @PrevProducts TABLE (GroupProductId INT, ProductId INT, FromDate DATE, ToDate DATE)
		INSERT INTO @PrevProducts (GroupProductId, ProductId, FromDate, ToDate)
		SELECT GroupProductId, ProductId, FromDate, ToDate FROM bodb_licensee.dbo.LA_f_GroupProduct(@ProductCodes,@PrevFDate,@PrevTDate) 

		;WITH CTE_PerformanceData AS (
			SELECT r.rptDate, r.SiteId, gp.GroupProductId  AS ProductId, r.CurrencyId
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.BetCount END) AS BetCount
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.Turnover END) AS Turnover
				,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE r.MemberWL + r.CommissionP END) AS MemberWL
				,SUM(CommissionA) AS BACommission
			FROM (
				SELECT rptDate, SiteId, ProductId, CurrencyId, Bettype
					,SUM(BetCount * CASE
										WHEN ISNULL(TicketType, 0) = 2 THEN 0
										WHEN @DrawFilter = 2 AND StatusId = 111 THEN 0
										ELSE 1 END) AS BetCount
					,SUM(Turnover * CASE
										WHEN ISNULL(TicketType, 0) = 2 THEN 0
										WHEN @DrawFilter NOT IN (2, 3) THEN 1
										WHEN StatusId = 111 THEN 0
										WHEN StatusId IN (114, 115) THEN 0.5
										ELSE 1 END) AS Turnover
					,SUM(CASE WHEN ISNULL(TicketType, 0) = 2 THEN 0 ELSE MemberWL END) AS MemberWL
					,SUM(CASE WHEN ProductId = 31 THEN CommissionP ELSE 0 END) AS CommissionP
					,SUM(CASE WHEN ProductId = 3 THEN CommissionA ELSE 0 END) AS CommissionA
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
				WHERE rptDate BETWEEN @PrevFDate AND @PrevTDate
					AND CurrencyId <> 20
					AND CustomerCategory NOT IN (27, 28)
					AND StatusId IN (111, 112, 113, 114, 115)
					AND (@Currency = 0 OR CurrencyId = @Currency)
				GROUP BY rptDate, SiteId, ProductId, CurrencyId, Bettype
				UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL -- sum data first
			) r
				INNER JOIN @PrevProducts gp ON r.ProductId = gp.ProductId AND r.rptDate BETWEEN gp.FromDate AND gp.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() gb ON r.Bettype = gb.Bettype
			GROUP BY r.rptDate, r.SiteId, gp.GroupProductId , r.CurrencyId
		)
		INSERT INTO #PerformanceData (rptDate, LicenseeId, PartyId, ProductId, CurrencyId, BetCount, Turnover, MemberWL, BACommission)
		SELECT d.rptDate, d.SiteId, p.PartyId, d.ProductId, d.CurrencyId, SUM(d.BetCount), SUM(d.Turnover), SUM(d.MemberWL), SUM(d.BACommission)
		FROM CTE_PerformanceData d
			INNER JOIN #_tmp_PartyChargeInfo p ON d.SiteId = p.LicenseeId AND d.ProductId = p.ProductId AND d.rptDate BETWEEN p.FromDate AND p.ToDate
		GROUP BY d.rptDate, d.SiteId, p.PartyId, d.ProductId, d.CurrencyId

		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
		)
		EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@Currencies = @Currencies
			,@FromDate = @PrevFDate
			,@ToDate = @PrevTDate
			,@IsConvertExRate = @IsConvert
			,@BaseCurrencyName = @BaseCurrencyName
			,@LicensingFeeTypeIds = '0,13'

		IF @isRecalRebate =1 AND @PrevFDate BETWEEN @RecalRebateEffectiveFrom AND @RecalRebateEffectiveTo AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SB')
		BEGIN
			DECLARE @Result_LastMonth TABLE
			(
				PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
				,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
				,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
			)
			INSERT INTO @Result_LastMonth
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds_AlekGroup
				,@ProductCodes = 'SB'
				,@Currencies = @Currencies
				,@FromDate = @PrevFDate
				,@ToDate = @PrevTDate
				,@IsConvertExRate = @IsConvert
				,@BaseCurrencyName = @BaseCurrencyName
				,@IsUsePreviousSetting = 1


			IF EXISTS (SELECT TOP 1 1 FROM @Result_LastMonth) 
			BEGIN
				UPDATE r
				SET r.Rebate = rl.Rebate
				FROM @Result r
				INNER JOIN @Result_LastMonth rl ON r.PartyId = rl.PartyId AND r.ProductId = rl.ProductId AND rl.LicensingFeeTypeId = 0
				WHERE r.LicensingFeeTypeId = 0 AND r.PartyId IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds_AlekGroup,','))
				AND r.IsPrevious IS NULL
				 
				DELETE FROM @Result_LastMonth
			END
		END

		UPDATE r
		SET r.IsPrevious = 1
			,r.LicensingFee = r.LicensingFee + CASE WHEN r.ProductId = 37 THEN 0 ELSE r.ExtraAmount END
			,r.BetCount = d.BetCount, r.Turnover = d.Turnover, r.MemberWL = d.MemberWL
			,r.BACommission = d.BACommission
		FROM @Result r
			LEFT JOIN (
				SELECT p.PartyId, p.ProductId
					,SUM(p.BetCount) AS BetCount
					,SUM(p.Turnover * e.Rate) AS Turnover
					,SUM(p.MemberWL * e.Rate) AS MemberWL
					,SUM(p.BACommission * e.Rate) AS BACommission
				FROM #PerformanceData p
					INNER JOIN @Exchange e ON p.CurrencyId = e.ExchangeId AND p.rptDate = e.ExchangeDate
				GROUP BY p.PartyId, p.ProductId
			) d ON r.PartyId = d.PartyId AND r.ProductId = d.ProductId
		WHERE r.IsPrevious IS NULL

		DROP TABLE #PerformanceData
	END

	DELETE FROM @Result
	WHERE ProductId = -37 AND NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE Value = 'SPR(CS)')

	-- Return data
	SELECT r.PartyId, p.PartyName + CASE WHEN r.IsChargedByMinFee = 1 THEN ' *' ELSE '' END AS PartyName
		,p.LaunchDate, r.TotalTrans, r.PreviousTotalTrans
		,CONVERT(MONEY, CASE WHEN r.TotalTrans = 0 THEN 0 ELSE r.Turnover/r.TotalTrans END) AS AverageBetValue
		,r.Turnover, r.PreviousTurnover, r.GrossWinLoss, r.PreviousGrossWinLoss
		,CONVERT(MONEY, CASE WHEN r.Turnover = 0 THEN 0 ELSE -r.GrossWinLoss/r.Turnover END) AS Margin
		,CONVERT(MONEY, CASE WHEN r.PreviousTurnover = 0 THEN 0 ELSE -r.PreviousGrossWinLoss/r.PreviousTurnover END) AS PreviousMargin
		,r.BACommission, r.PreviousBACommission, r.AmountDueToBA, r.PreviousAmountDueToBA
		,r.SportsbookFee, r.PreviousSportsbookFee, r.OtherProductsFee, r.PreviousOtherProductsFee
		,r.DiscountSportsbook, r.PreviousDiscountSportsbook, r.DiscountOthers, r.PreviousDiscountOthers
		,r.RebateSportsbook, r.PreviousRebateSportsbook, r.RebateOthers, r.PreviousRebateOthers
		,r.PromotionSportsbook, r.PreviousPromotionSportsbook,  r.PlayerTipsSportsbook, r.PreviousPlayerTipsSportsbook, r.SponsorshipSportsbook, r.PreviousSponsorshipSportsbook
		,r.PromotionOthers AS PromotionOthers, r.PreviousPromotionOthers AS PreviousPromotionOthers
		,r.TotalLicensingFee, r.PreviousTotalLicensingFee
		,r.PartyId, CONVERT(BIT, 1) AS IsSelected -- Old format
	FROM (
		SELECT PartyId
			,CONVERT(BIT,	MAX(CASE WHEN IsPrevious = 0 THEN CONVERT(TINYINT, IsChargedByMinFee) ELSE 0 END)) AS IsChargedByMinFee
			,CONVERT(BIT,	MAX(CASE WHEN IsPrevious = 0 THEN CONVERT(TINYINT, IsChargedByGroupMinFee) ELSE 0 END)) AS IsChargedByGroupMinFee
			,CONVERT(INT,	SUM(CASE WHEN IsPrevious = 0 THEN BetCount ELSE 0 END)) AS TotalTrans
			,CONVERT(INT,	SUM(CASE WHEN IsPrevious = 1 THEN BetCount ELSE 0 END)) AS PreviousTotalTrans
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 THEN Turnover ELSE 0 END)) AS Turnover
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 THEN Turnover ELSE 0 END)) AS PreviousTurnover
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 THEN MemberWL ELSE 0 END)) AS GrossWinLoss
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 THEN MemberWL ELSE 0 END)) AS PreviousGrossWinLoss
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 3 THEN BACommission ELSE 0 END)) AS BACommission
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 3 THEN BACommission ELSE 0 END)) AS PreviousBACommission
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 3 THEN LicensingFee ELSE 0 END)) AS AmountDueToBA
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 3 THEN LicensingFee ELSE 0 END)) AS PreviousAmountDueToBA
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 0 THEN LicensingFee ELSE 0 END)) AS SportsbookFee
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 0 THEN LicensingFee ELSE 0 END)) AS PreviousSportsbookFee
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId NOT IN (0, 3, 37, 74, -37) THEN LicensingFee ELSE 0 END)) AS OtherProductsFee
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId NOT IN (0, 3, 37, 74, -37) THEN LicensingFee ELSE 0 END)) AS PreviousOtherProductsFee
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 0 THEN Discount ELSE 0 END)) AS DiscountSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 0 THEN Discount ELSE 0 END)) AS PreviousDiscountSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId <> 0 THEN Discount ELSE 0 END)) AS DiscountOthers
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId <> 0 THEN Discount ELSE 0 END)) AS PreviousDiscountOthers
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 0 THEN Rebate ELSE 0 END)) AS RebateSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 0 THEN Rebate ELSE 0 END)) AS PreviousRebateSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId <> 0 THEN Rebate ELSE 0 END)) AS RebateOthers
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId <> 0 THEN Rebate ELSE 0 END)) AS PreviousRebateOthers
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 37 THEN LicensingFee ELSE 0 END)) AS PromotionSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 37 THEN LicensingFee ELSE 0 END)) AS PreviousPromotionSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 74 THEN ExtraAmount ELSE 0 END)) AS PlayerTipsSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 74 THEN ExtraAmount ELSE 0 END)) AS PreviousPlayerTipsSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = 37 THEN ExtraAmount ELSE 0 END)) AS SponsorshipSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = 37 THEN ExtraAmount ELSE 0 END)) AS PreviousSponsorshipSportsbook
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 0 AND ProductId = -37 THEN ExtraAmount ELSE 0 END)) AS PromotionOthers
			,CONVERT(MONEY, SUM(CASE WHEN IsPrevious = 1 AND ProductId = -37 THEN ExtraAmount ELSE 0 END)) AS PreviousPromotionOthers
			,CONVERT(MONEY, SUM(CASE
									WHEN IsPrevious = 1 OR ProductId = 3 THEN 0
									WHEN ProductId = 37 THEN - LicensingFee - ExtraAmount
									WHEN ProductId = 74 THEN ExtraAmount
									WHEN ProductId = -37 THEN -ExtraAmount - Rebate
									ELSE LicensingFee - Discount - Rebate END)) AS TotalLicensingFee
			,CONVERT(MONEY, SUM(CASE
									WHEN IsPrevious = 0 OR ProductId = 3 THEN 0
									WHEN ProductId = 37 THEN - LicensingFee - ExtraAmount
									WHEN ProductId = 74 THEN ExtraAmount
									WHEN ProductId = -37 THEN -ExtraAmount - Rebate
									ELSE LicensingFee - Discount - Rebate END)) AS PreviousTotalLicensingFee
		FROM @Result
		GROUP BY PartyId
	) r
		INNER JOIN @PartyList p ON r.PartyId = p.PartyId
	WHERE (
		@LicenseePaying = 0
		OR (@LicenseePaying = 1 AND r.IsChargedByMinFee = 0 AND r.IsChargedByGroupMinFee = 0)
		OR (@LicenseePaying = 2 AND r.IsChargedByMinFee = 1)
		OR (@LicenseePaying = 3 AND r.IsChargedByGroupMinFee = 1)
	)
	AND (
		r.TotalTrans > 0 OR r.PreviousTotalTrans > 0
		OR r.SportsbookFee > 0 OR r.PreviousSportsbookFee > 0
		OR r.PromotionOthers > 0 OR r.PreviousPromotionOthers > 0
	)

	DROP TABLE #_tmp_PartyChargeInfo
	DROP TABLE #tmp_licenseeOIC
END
GO