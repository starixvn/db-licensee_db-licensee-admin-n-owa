/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_3rdProductSettlement]
	@PartyIds			VARCHAR(4000)
	,@ProductCodes		VARCHAR(500)
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@Timezone			INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20210915@Danny]
 * Task  : Get all 3rd products settlement information between OW and others parties
 * Revisions
	- 20210306@Danny: Init SP [#155402]
	- 20211122@Percy: Enhance code get data from rpt_ThirdPartyWL_ExtraGMT table [RedmineID: #155402]
	- 20220110@Danny: SG - Jackpot prize integration [#167089]
	- 20220218@Danny: Allbet - Promotion integration [#167510]
	- 20220407@Percy: Calculate Licensee Fee base on LicenseeContribution [RedmineID: #171190]
	- 20220328@Danny: Intergrate Guaranteed Gaming [#167626]
	- 20210623@Danny: Fix PaytoSuplier PPL issue [#168387]
	- 20221027@Danny: MG-RNG ofer Tournament prize [RedmineID: #176986]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20230222@Danny: Remove hard-code bettype And ProductID [#183739]
	- 20230410@Danny: Change PayToSupplier fomular [RedmineID: #186543]
	- 20230518@Danny: Integrate YeeBet [RedmineID: #187948]
	- 20230608@Danny: Integrate Promotion Prize - PG Soft [RedmineID: #188997]
	- 20230807@Danny: Handle JV group formula (all products) [RedmineID: #190901]
	- 20231017@Danny: Change AGC 3rd billing term [RedmineID: #195338]
	- 20231109@Danny: Intergrate World Entertainment Live Casino [#194603]
	- 20231218@Danny: Integrate Promotion Prize - Live22 [RedmineID: #197267]
	- 20240222@Danny: AGC - JP, Contribution, Promotion prize integration [#197268]
	- 20240123@Danny: Change Credit licensing fee fomular [RedmineID: #197267]
	- 20240301@Danny: Merge virtual sports product [RemineID: #199478]
	- 20240521@Danny: support Inhouse Product [RemineID: #200955]

 * Param's Explanation:
 *				@Timezone:  = 0  GMT 0 
							= 1: GMT-4
						    = 2: GMT+8	
	
 * Example
	- GTM-4 All Products supported
	EXEC LA_Rpt_3rdProductSettlement @PartyIDs='14,20,148,493,70,56,275,558,316,459,307,15,142,95,58,460,43,457,526,153,76,101,97,114,383,453,530,218,448,81,555,46,676,143,38,92,271,489,146,89,354,82,210,150,91,78,83,52,533,461,93,64,253,353,491,154,260,675,47,361,39,84,77,85,477,44,48,452,86,42,170,323,475,570,571,572,573,574,575,583,584,586,151,465,19,136,312,29,175,276,348,40,171,167,194,63,470,308,33,90,466,464,455,61,462,525,415,158,59,447,334,41,72,482,124,68,67,433,471,34,387,403,117,487,24,647,74,409,429,213,346,412,217,396,207,652,35,370,331,436,367,347,332,165,398,206,419,439,531,414,168,395,449,582,664,441,62,481,127,374,71,653,169,73,246,456,166,80,36,411,417,578,446,469,534,37,490,364,66,31,360,485,162,488,605,317,418,473,88,96,604,329,333,356,476,75,410,435,397,468,404,434,619,322,576,580,607,608,609,610,611,612,613,614,615,616,617,618,623,624,625,638,639,640,626,627,628,629,630,631,632,633,634,635,636,637,641,642,643,644,645,646,585,69,432,443,55,401,325,349,431,416,369,402,764,524,545,53,392,363,421,305,602,407,606,463,445,60,65,17,450,386,26,674,304,405,100,358,49,87,79,157,16,22,422,420,388,440,451,321,190,45,54,21,389,577,620,621,622,587,588,99,27,444,23,30,385,324,25',
								 @ProductCodes = 'SB_BetBuilder,SB_MuayThai,NG,VS,KN,AGC,CB,AB,VB,NG2,FW,CO,VS2,LT,BX,PP,CC,SG,SAG,TG,SXG,IBCLC,BBIN,VS3,RNGW,WM,ION,PGS,JK,BGG,GDG,MXG,HB,CG,PPL,AP,APM,BTC',  
								 @FromDate	= '20210501', 
								 @ToDate	= '20210531', 
								 @BaseCurrencyName = 'EUR', 
								 @Timezone = 1
	
	- GTM+8 All Products supported
	EXEC LA_Rpt_3rdProductSettlement @PartyIDs='14,20,148,493,70,56,275,558,316,459,307,15,142,95,58,460,43,457,526,153,76,101,97,114,383,453,530,218,448,81,555,46,676,143,38,92,271,489,146,89,354,82,210,150,91,78,83,52,533,461,93,64,253,353,491,154,260,675,47,361,39,84,77,85,477,44,48,452,86,42,170,323,475,570,571,572,573,574,575,583,584,586,151,465,19,136,312,29,175,276,348,40,171,167,194,63,470,308,33,90,466,464,455,61,462,525,415,158,59,447,334,41,72,482,124,68,67,433,471,34,387,403,117,487,24,647,74,409,429,213,346,412,217,396,207,652,35,370,331,436,367,347,332,165,398,206,419,439,531,414,168,395,449,582,664,441,62,481,127,374,71,653,169,73,246,456,166,80,36,411,417,578,446,469,534,37,490,364,66,31,360,485,162,488,605,317,418,473,88,96,604,329,333,356,476,75,410,435,397,468,404,434,619,322,576,580,607,608,609,610,611,612,613,614,615,616,617,618,623,624,625,638,639,640,626,627,628,629,630,631,632,633,634,635,636,637,641,642,643,644,645,646,585,69,432,443,55,401,325,349,431,416,369,402,764,524,545,53,392,363,421,305,602,407,606,463,445,60,65,17,450,386,26,674,304,405,100,358,49,87,79,157,16,22,422,420,388,440,451,321,190,45,54,21,389,577,620,621,622,587,588,99,27,444,23,30,385,324,25',
								 @ProductCodes = 'FW,SG,SAG,SXG,WM,JK,CG',  
								 @FromDate	= '20210501', 
								 @ToDate	= '20210531', 
								 @BaseCurrencyName = 'EUR', 
								 @Timezone = 2

	- GTM+0 All Products supported
	EXEC LA_Rpt_3rdProductSettlement @PartyIDs='14,20,148,493,70,56,275,558,316,459,307,15,142,95,58,460,43,457,526,153,76,101,97,114,383,453,530,218,448,81,555,46,676,143,38,92,271,489,146,89,354,82,210,150,91,78,83,52,533,461,93,64,253,353,491,154,260,675,47,361,39,84,77,85,477,44,48,452,86,42,170,323,475,570,571,572,573,574,575,583,584,586,151,465,19,136,312,29,175,276,348,40,171,167,194,63,470,308,33,90,466,464,455,61,462,525,415,158,59,447,334,41,72,482,124,68,67,433,471,34,387,403,117,487,24,647,74,409,429,213,346,412,217,396,207,652,35,370,331,436,367,347,332,165,398,206,419,439,531,414,168,395,449,582,664,441,62,481,127,374,71,653,169,73,246,456,166,80,36,411,417,578,446,469,534,37,490,364,66,31,360,485,162,488,605,317,418,473,88,96,604,329,333,356,476,75,410,435,397,468,404,434,619,322,576,580,607,608,609,610,611,612,613,614,615,616,617,618,623,624,625,638,639,640,626,627,628,629,630,631,632,633,634,635,636,637,641,642,643,644,645,646,585,69,432,443,55,401,325,349,431,416,369,402,764,524,545,53,392,363,421,305,602,407,606,463,445,60,65,17,450,386,26,674,304,405,100,358,49,87,79,157,16,22,422,420,388,440,451,321,190,45,54,21,389,577,620,621,622,587,588,99,27,444,23,30,385,324,25',
								 @ProductCodes = 'PP,PPL',  
								 @FromDate	= '20210501', 
								 @ToDate	= '20210531', 
								 @BaseCurrencyName = 'EUR', 
								 @Timezone = 0
 */

BEGIN
	SET NOCOUNT ON

	-- Specical bettype
	DECLARE @ProductCodesGMT VARCHAR(1000),
			@ProductCodes3rd VARCHAR(1000),
			@12BetGroupId		INT = -1,
			@CreditGroupId		INT = 999,
			@TianboPartyId		INT = 432,
			@BobbetPartyId		INT = 346,
			@CN88PartyId		INT,
			@FDATE				DATE = @FromDate,
			@TDATE				DATE = @ToDate,
			@FDATE_GMT			DATE = DATEADD(DAY, -1, @FromDate),
			@TDATE_GMT			DATE = DATEADD(DAY, 1, @ToDate),
			@MinSite			INT, 
			@MaxSite			INT,
			@Allbet				INT,
			@ProductRptbettingSource VARCHAR(1000) = '',
			@ShareRate			MONEY = 0.03,
			@BetBuilderRate3rd  MONEY = 0.04, 
			@BetBuilderBetTypeId INT = 38,
			@ExchangeCutoffDate SMALLDATETIME,
			@MergeVSCutoffDate	SMALLDATETIME = '2024-03-01'

	SELECT @ExchangeCutoffDate = f.CutoffDate FROM dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'

	-- PPL param
	DECLARE @BaseCurrencies		TABLE (ExchangeId INT, BaseCurrencyName VARCHAR(20))
	DECLARE @BaseCurrencyRate   TABLE (ExchangeId INT, ExchangeDate DATETIME, BaseCurrencyName VARCHAR(20), Rate FLOAT)
	DECLARE @CurrencyId			INT, 
			@CurrencyName		VARCHAR(100)

	DECLARE @ExtraAmtGroupBettype TABLE (ProductID INT, TypeID SMALLINT, Bettype INT)
	DECLARE @ExtraAmtProduct TABLE (ProductID INT)
	DECLARE @PartyIdInput TABLE( PartyId INT)
	DECLARE @productDataView TABLE 
	(
		ProductID						INT
		,ProductCode					VARCHAR(50) 
		,ProductName					VARCHAR(50)
		,isKeepNegativeFee				BIT 
		,isKeepNegativePayToSupplier	BIT 
		,isRptBettingSource				TINYINT
		,isRptBettingBySportSource		TINYINT
		,isSupportGMT8					BIT
		,isSupportGMT0					BIT
		,isRptLicCashoutSummarySource	BIT
	)
	DECLARE @bettypeExtraGMT TABLE (bettype INT, ProductID INT)

	DECLARE @CBShare AS TABLE (
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			BaseCurrencyId	SMALLINT,
			TypeId			SMALLINT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)

	-- Play currency settings
	DECLARE @PlayCurrencySettings TABLE(
			SiteId			INT,
			MemberCurrency	INT,
			PlayCurrency	INT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)

	DECLARE @SharingCharge TABLE (
			PartyId		INT,
			ProductID	INT,
			FromDate	DATE,
			ToDate		DATE,
			Rate		MONEY
	 )

	DECLARE @AllbetBettype TABLE (Bettype INT)

	-- Bettype list of Products get data from rptBetting
	DECLARE @bettype TABLE(Bettype INT , ProductID INT, SubProduct VARCHAR(500))
	DECLARE @MinSite_rpt_Betting	INT,
			@MaxSite_rpt_Betting	INT,
			@MinBettype_rpt_Betting INT,
			@MaxBettype_rpt_Betting INT
	-- Hard Rate by bettype And IsDeposit (CC & VB)
	DECLARE @CC_MidasRate3rd			DECIMAL(4,3) = 0.035,
			@CC_NormalRate3rd			DECIMAL(4,3) = 0.025,
			@VB_depositBlueprint3rd		DECIMAL(4,3) = 0.045,
			@VB_depositNotBlueprint3rd	DECIMAL(4,3) = 0.035,
			@VB_creditBlueprint3rd		DECIMAL(4,3) = 0.03,
			@VB_creditNotBlueprint3rd	DECIMAL(4,3) = 0.02

	-- Result
	DECLARE @Total TABLE (
		ParentId		INT,
		ParentName		NVARCHAR(100),
		ProductID		INT,
		TotalTrans		INT,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY DEFAULT 0,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20),
		IncomeOnBB				MONEY DEFAULT 0,
		IncomeOnProfitSharing   MONEY DEFAULT 0,
		AmtDueToOnBB			MONEY DEFAULT 0,
		AmtDueToOnProfitSharing MONEY DEFAULT 0,
		CustomerWinLossBA		MONEY DEFAULT 0,
		CommissionA				MONEY DEFAULT 0
	)

	DECLARE @PPTotal TABLE (
			ParentId			INT,
			ParentName		NVARCHAR(100),
			ProductID		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			WinPrizeAmount	MONEY,
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY,
			Currency		VARCHAR(20)
		)

	-- AGC apply range
	DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

	-- SAG param
	DECLARE @OneWorks			INT = 1, 
			@Boping				INT = 11, 
			@Zelianta			INT = 98, 
			@BopingAndZelianta	INT = 99
	DECLARE @SAG_ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

	-- PP param
	DECLARE @PP_BaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT)
	DECLARE @NumberOfTiers				INT = 2,
			@CreditBaseCurrencyName		VARCHAR(10), 
			@CreditBaseCurrencyId		INT,
			@TotalAmount_BasedOn_CreditBaseCurrencyName MONEY, 
			@TotalAmountWinLossBase		MONEY
	DECLARE @RateOfCredit AS TABLE (
			RowIndex TINYINT IDENTITY(1,1),
			PartyId			INT,
			ProductID		INT,
			Rate			MONEY,
			MinAmount		MONEY,
			MaxAmount		MONEY,
			BaseCurrencyId	SMALLINT
		)

	-- CB param
	DECLARE @CBChargeInfo TABLE (PartyID INT, LicenseeID INT, DI_Rate MONEY, ChargeType INT, Fromdate DATETIME, ToDate	DATETIME)
	DECLARE @CBBaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT)
	-- get commissionRate, cashinshareRate for every Period in @CBShare
	DECLARE @RateByPeriod AS TABLE (FromDate DATETIME, ToDate DATETIME, CommissionRate FLOAT,CashInShareRate FLOAT)
	DECLARE @TotalByPeriod AS TABLE (FromDate DATETIME, ToDate DATETIME, TurnoverForCommision MONEY, CashInAmount MONEY)
	DECLARE @CBBaseCurrency VARCHAR(10)
	

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)

	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY -- Lic fee chargeType = 1
		,Rate3rd		MONEY -- 3rd fee chargeType = 1
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	
		,ChargeRate09	MONEY DEFAULT 0 -- @@DepositServiceCharge
		,ChargeRate10	MONEY DEFAULT 0 -- @CreditServiceCharge
		,ChargeRate11	MONEY DEFAULT 0 -- @RollingRollingCommType
		,ChargeRate12	MONEY DEFAULT 0 -- @TipChargeType

		,CashoutCommissionRate	MONEY DEFAULT 0
		,IncomeOnBBRate			MONEY DEFAULT 0
		,AB_ServiceCharge		MONEY DEFAULT 0
		,Fromdate3rd		SMALLDATETIME
		,Todate3rd			SMALLDATETIME
	)
	CREATE CLUSTERED INDEX cix_#ChargeRate ON #ChargeRate(ProductID, LicenseeID, isDeposit, Fromdate, Todate)

	CREATE TABLE #3rdRate (PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	-- #ChargeInfo Rate
	CREATE TABLE #ChargeInfoWithCredit (PartyID INT, ProductID INT,  IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, DI_Rate MONEY, ChargeType INT, LicenseeID INT, ChargeID INT)
	CREATE TABLE #3rdRatePPL (PartyId INT, ProductID INT, FromDate DATE, ToDate DATE, CurrencyId INT, MinAmount MONEY, MaxAmount MONEY, Rate FLOAT)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)

	CREATE TABLE #AllbetPlayCurrency (	
			
			SiteId			INT,
			MemberCurrency	INT,
			PlayCurrency	INT,
			FromDate		DATETIME,
			ToDate			DATETIME,
			Bettype			INT
	)

	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID			INT,
		ProductID		INT,
		Winlostdate		DATETIME,
		CurrencyId		INT, 
		TotalTrans		INT,
		Turnover		MONEY DEFAULT 0,
		CustomerWinLoss MONEY DEFAULT 0,
		LicenseeWinloss MONEY DEFAULT 0,
		LicensingFee	MONEY DEFAULT 0,
		PayToSupplier	MONEY DEFAULT 0,
		Promotion		MONEY DEFAULT 0,
		ExtraPT			MONEY DEFAULT 0,
		ApplyValue		MONEY DEFAULT 0,
		ParentID		INT,
		ValidBetAmount	MONEY DEFAULT 0,
		isDeposit		BIT,
		-- MuayThai column
		WLShare			MONEY DEFAULT 0, 
		LicComm			MONEY DEFAULT 0, 
		CommShare		MONEY DEFAULT 0,
		-- BetBuilder Column
		CustomerWinLossSB MONEY DEFAULT 0,
		CustomerWinLossBA MONEY DEFAULT 0,
		CommissionA		MONEY DEFAULT 0,
		CommissionS		MONEY DEFAULT 0,
		--SAgaming column
		TipAmount 		MONEY DEFAULT 0,
		RollingComm		MONEY DEFAULT 0,
		NetWinLoss		MONEY DEFAULT 0,
		CompanyTipShare MONEY DEFAULT 0,
		RoyaltyFee		MONEY DEFAULT 0,
		-- PP,SG colum
		JackpotPrize	MONEY DEFAULT 0,
		LicenseeContribution	MONEY DEFAULT 0,
		FullContribution		MONEY DEFAULT 0,
		LicenseeChargeRate	MONEY DEFAULT 0,
		-- Allbet	
		Playcurrency		INT,
		ServiceChargeOriginal MONEY DEFAULT 0,
		RebateCommissionOriginal MONEY DEFAULT 0,
		-- CB
		TurnoverForCommision MONEY DEFAULT 0,
		CBPrize				MONEY DEFAULT 0,
		CashOut				MONEY DEFAULT 0,
		CashInAmount		MONEY DEFAULT 0,
		-- CO
		BuyBackAmountTotal	MONEY DEFAULT 0, 
		TicketsPayout		MONEY DEFAULT 0, 
		CashoutCommission	MONEY DEFAULT 0, 
		IncomeOnBB			MONEY DEFAULT 0,
		IncomeOnProfitSharing	MONEY DEFAULT 0,
		AmtDueToOnBB			MONEY DEFAULT 0,
		AmtDueToOnProfitSharing MONEY DEFAULT 0
		)
	CREATE CLUSTERED INDEX cix_#TempData ON #TempData(ProductID, PartyID, Winlostdate, CurrencyId )

	-- Result
	CREATE TABLE #Result  (
		ParentId		INT,
		ParentName		NVARCHAR(100),
		PartyId			INT,
		ProductID		INT,
		TotalTrans		INT,
		CustomerWinLoss	MONEY DEFAULT 0,
		LicenseeWinLoss	MONEY DEFAULT 0,
		LicensingFee	MONEY DEFAULT 0,
		ExtraPT 		MONEY DEFAULT 0,
		PayToSupplier	MONEY DEFAULT 0,
		Currency		VARCHAR(20),
		IsKeepNegativeAmount BIT,
		WLShare			MONEY DEFAULT 0, 
		LicComm			MONEY DEFAULT 0, 
		CommShare		MONEY DEFAULT 0,
		CustomerWinLossSB MONEY DEFAULT 0,
		CustomerWinLossBA MONEY DEFAULT 0,
		CommissionA		MONEY DEFAULT 0,
		CommissionS		MONEY DEFAULT 0,
		CompanyTipShare MONEY DEFAULT 0,

		IncomeOnBB				MONEY DEFAULT 0,
		IncomeOnProfitSharing 	MONEY DEFAULT 0,
		AmtDueToOnBB			MONEY DEFAULT 0,
		AmtDueToOnProfitSharing	MONEY DEFAULT 0,
		LicenseeChargeRate		MONEY DEFAULT 0,
		JackpotPrize			MONEY DEFAULT 0,
		LicenseeContribution	MONEY DEFAULT 0,
		FullContribution		MONEY DEFAULT 0,
		IsDeposit				BIT,
		Promotion				MONEY DEFAULT 0
	)
	CREATE CLUSTERED INDEX cix_#Result ON #Result(ProductID, PartyID)

	-- Get value
	SELECT @CN88PartyId = a.PartyID FROM dbo.OAS_Party a WITH(NOLOCK) WHERE a.PartyName='CN88'
	SELECT @Allbet  =  PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName='Allbet' AND PartyType=3

	-- Insert @PartyIds param input
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	INSERT INTO @PartyIdInput(PartyId) SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds,',')
	
	-- Insert product detail by source (rptBetting, rptBettingByProduct, rpt_ThirdPartyWL_ExtraGMT, ....)
	INSERT INTO @productDataView(ProductID, ProductCode, ProductName, isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0, isRptLicCashoutSummarySource) 
	EXEC LA_3rdProductByTimeZoneSel @ProductCodes = @ProductCodes, @Timezone = @Timezone, @isShowDetail = 1

	IF @FromDate >= @MergeVSCutoffDate
		UPDATE @productDataView SET isKeepNegativeFee = 1 WHERE ProductID = 5
	
	-- Handle @ProductCodes (MuayThai And BetBuilder have same ProductCode)
	SELECT @ProductCodes = ''
	;WITH CTE_Product AS 
	(
		SELECT DISTINCT CASE WHEN ProductCode IN ('SB_MuayThai','SB_BetBuilder','BTC','SLT') THEN 'SB' ELSE ProductCode END  ProductCode 
		FROM @productDataView
	)
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM CTE_Product

	-- Handle @ProductCodesGMT (Include Product support GMT billing)
	SELECT @ProductCodesGMT = COALESCE(@ProductCodesGMT + ',', '') + CONVERT(VARCHAR(10), ProductCode) FROM @productDataView WHERE isSupportGMT0 = 1 OR isSupportGMT8 = 1

	-- Handle @ProductCodes3rd 
	SET @ProductCodes3rd = @ProductCodes
	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 69)
		SELECT @ProductCodes3rd =@ProductCodes3rd + ',BTC'

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 63)
		SELECT @ProductCodes3rd =@ProductCodes3rd + ',SLT'

	IF @FromDate >= @MergeVSCutoffDate 
		AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value IN ('VS2','LG','VS4'))
		AND NOT EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value IN ('VS'))
	BEGIN
		SELECT @ProductCodes = @ProductCodes + ',VS'
	END

	-- Bettype List of Products that support GMT billing
	INSERT INTO @bettypeExtraGMT(bettype, ProductID)
	SELECT	DISTINCT la.Bettype, la.ProductID
	FROM	LA_f_BettypeProductMapping(0,@ProductCodesGMT) la

	-- Get parties list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	DELETE #PartyList
	WHERE PartyId NOT IN (SELECT z.PartyId FROM @PartyIdInput z) AND ParentId <> 0

	-- Apply for all products
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
	
	-- Get 3rd Rate
	;WITH r AS(	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r. Todate, r.IsParent	
			FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCodes3rd, 'OA') r 
			WHERE r.ChargeType = 1
		 ) 
	INSERT INTO #3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
	SELECT DISTINCT p.PartyId, r.ProductID, CASE WHEN ProductID = 10 OR (ProductID = 32 AND IsDeposit = 0) THEN 0 ELSE r.DI_Rate END, r.IsDeposit, r.Fromdate, r.Todate 
	FROM r
	INNER JOIN #PartyList p ON ( 
									(p.ParentId = r.PartyID AND r.ProductID <> 31) 
									OR 
									(
										(p.ParentId = r.PartyID AND r.ProductID = 31 AND r.IsParent = 1 AND p.PartyId NOT IN (Select r.PartyID FROM r WHERE r.IsParent = 0)) 
										OR
										(p.PartyId = r.PartyID AND r.ProductID = 31 AND r.IsParent = 0)
									)
								)
	CREATE CLUSTERED INDEX CIX_#3rdRate ON #3rdRate(ProductID, PartyID)

	INSERT INTO #ChargeInfoWithCredit (PartyID, ProductID, IsDeposit, Fromdate, Todate, DI_Rate, ChargeType, LicenseeID, ChargeID )
	SELECT PartyID, ProductID, IsDeposit, Fromdate, Todate, CASE WHEN ProductID = 22 AND isDeposit = 0 THEN 0 ELSE DI_Rate END, ChargeType, LicenseeID, ChargeID FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCodes) c

	IF EXISTS(SELECT 1 FROM @productDataView WHERE ProductID IN (69 ,63)) 
	BEGIN
		INSERT INTO #ChargeInfoWithCredit (PartyID, ProductID, IsDeposit, Fromdate, Todate, DI_Rate, ChargeType, LicenseeID, ChargeID )
		SELECT PartyID, 69 AS ProductID, IsDeposit, Fromdate, Todate, CASE WHEN IsDeposit = 0 THEN 0 ELSE  DI_Rate END , ChargeType, LicenseeID, ChargeID  --Clone BTC setting 
		FROM	#ChargeInfoWithCredit 
		WHERE ProductID = 0 AND EXISTS(SELECT 1 FROM @productDataView WHERE ProductID = 69 )
		UNION ALL 
		SELECT PartyID, 63 AS ProductID, IsDeposit, Fromdate, Todate, CASE WHEN IsDeposit = 0 THEN 0 ELSE  DI_Rate END , ChargeType, LicenseeID, ChargeID  --Clone SLT setting 
		FROM	#ChargeInfoWithCredit 
		WHERE ProductID = 0 AND EXISTS(SELECT 1 FROM @productDataView WHERE ProductID = 63 )

		IF NOT EXISTS(SELECT 1 FROM @productDataView WHERE ProductID = 0 )
		BEGIN
			DELETE FROM  #ChargeInfoWithCredit WHERE ProductID = 0
		END
	END

	IF @FromDate >= @MergeVSCutoffDate 
	BEGIN
		DELETE FROM #ChargeInfoWithCredit WHERE ProductID IN (27, 77, 83) 

		INSERT INTO #ChargeInfoWithCredit (PartyID, ProductID, IsDeposit, Fromdate, Todate, DI_Rate, ChargeType, LicenseeID, ChargeID )
		SELECT PartyID, x.ProductID AS ProductID, IsDeposit, Fromdate, Todate, CASE WHEN IsDeposit = 0 THEN 0 ELSE  DI_Rate END , ChargeType, LicenseeID, ChargeID  --Clone VS setting 
		FROM	#ChargeInfoWithCredit t
		CROSS APPLY (
			SELECT 27 AS ProductID --VS2
			UNION ALL SELECT 77 --VS3
			UNION ALL SELECT 83	--VS4
		) x
		WHERE t.ProductID = 5

	END

	CREATE CLUSTERED INDEX cix_#ChargeInfoWithCredit ON #ChargeInfoWithCredit(ProductID, PartyID, ChargeType)

	-- #ChargeInfo Details
	INSERT INTO #ChargeRate(ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate, Fromdate3rd, Todate3rd)
	SELECT DISTINCT CASE WHEN (c.ProductID = 24 AND c.isDeposit = 0) OR (c.ProductID = 32 AND c.isDeposit = 0) THEN -1 ELSE c.ChargeID END, 
					c.PartyID, 
					c.LicenseeID, 
					ISNULL(c.isDeposit,0), 
					c.ProductID, 
					CASE WHEN c.ProductID IN (24, 32, 36) AND c.isDeposit = 0  THEN 0 ELSE c.DI_Rate END AS Rate, 
					CASE WHEN c.ProductID IN (5,27) AND c.isDeposit = 0 THEN 0.01 
					     WHEN c.ProductID = 2 THEN 0.5
						 WHEN c.ProductID IN (8,28) THEN CASE WHEN c.PartyId = @CN88PartyId THEN 0.015
															  WHEN c.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02
															  WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036
															  WHEN p.ParentId IN (@CreditGroupId, @12BetGroupId) OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
															  ELSE 0.05 END
						 WHEN c.ProductID = 40 THEN CASE WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN CASE WHEN p.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02 ELSE 0.036  END 
														 ELSE ISNULL(r.DI_Rate,0)  END
						 ELSE ISNULL(r.DI_Rate,0) END AS Rate3rd, 
					c.Fromdate, 
					c.Todate,
					r.Fromdate AS Fromdate3rd, 
					r.Todate AS Todate3rd
	FROM #ChargeInfoWithCredit c
	INNER JOIN #PartyList p ON c.PartyID = p.PartyId
	LEFT JOIN #3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID AND r.ProductID NOT IN (0, 65)
	WHERE 
		(
			(c.DI_Rate = 0 AND c.isDeposit = 0) 
			OR (c.DI_Rate > 0 and c.isDeposit = 1) 
			OR c.ProductID IN (0,2,23,24,32)
		)  AND c.ChargeType = 1
		AND c.ProductID NOT IN (15, 21, 25)
	
	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 70)
	BEGIN
		;WITH cte AS
		(
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.ChargeType
			FROM (	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.ChargeType
				FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'FGGL', 'OA') r 
				WHERE r.ChargeType = 11
			 ) r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
		)
		UPDATE t
		SET		t.ChargeRate11 = ISNULL(u1.DI_Rate,0)
		FROM	#ChargeRate t
	
		LEFT JOIN cte u1 ON t.PartyID = u1.PartyID AND t.ProductID = u1.ProductID AND u1.ChargeType = 11
		WHERE t.ProductID = 70
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 76)
	BEGIN
		;WITH cte AS
		(
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.ChargeType
			FROM (	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.ChargeType
				FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'YB', 'OA') r 
				WHERE r.ChargeType = 11
			 ) r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
		)
		UPDATE t
		SET		t.ChargeRate11 = ISNULL(u1.DI_Rate,0)
		FROM	#ChargeRate t
	
		LEFT JOIN cte u1 ON t.PartyID = u1.PartyID AND t.ProductID = u1.ProductID AND u1.ChargeType = 11
		WHERE t.ProductID = 76
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 80)
	BEGIN
		;WITH cte AS
		(
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.ChargeType
			FROM (	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.ChargeType
				FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'WE', 'OA') r 
				WHERE r.ChargeType = 11
			 ) r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
		)
		UPDATE t
		SET		t.ChargeRate11 = ISNULL(u1.DI_Rate,0)
		FROM	#ChargeRate t
	
		LEFT JOIN cte u1 ON t.PartyID = u1.PartyID AND t.ProductID = u1.ProductID AND u1.ChargeType = 11
		WHERE t.ProductID = 80
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 15)
	BEGIN
		INSERT INTO #ChargeRate(ChargeID,PartyID, LicenseeID,isDeposit, ProductID, Fromdate, Todate)
		SELECT DISTINCT ci.ChargeID, ci.partyid, ci.LicenseeID, ISNULL(ci.isDeposit,0),  ci.ProductID, ci.Fromdate,ci.Todate			
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'CB', 'OA', 1) ci 	
		WHERE ci.ChargeType = 6 AND ci.LicenseeID IS NOT NULL

		INSERT INTO @CBShare(Rate, MinAmount, MaxAmount, BaseCurrencyId, TypeId, FromDate, ToDate)
		SELECT	ci.Rate, MinAmount, MaxAmount, BaseCurrencyId, ChargeType,
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
		FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE FromParty = 1 AND ProductID = 15 AND ChargeType IN (6,7) AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
			@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
			ci.FromDate BETWEEN @FromDate AND @ToDate OR
			ci.ToDate BETWEEN @FromDate AND @ToDate
		)
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 39)
	BEGIN
		UPDATE t
		SET		t.ChargeRate12 = ISNULL(u.DI_Rate,0)
		FROM	#ChargeRate t
		LEFT JOIN LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SAG') u ON t.PartyID = u.PartyID AND t.ProductID = u.ProductID AND u.ChargeType = 12
		WHERE t.ProductID = 39

		;WITH cte AS
		(
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.ChargeType
			FROM (	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.ChargeType
				FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'SAG', 'OA') r 
				WHERE r.ChargeType IN (10, 11)
			 ) r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
		)
		UPDATE t
		SET		t.ChargeRate10 = ISNULL(u.DI_Rate,0),
				t.ChargeRate11 = ISNULL(u1.DI_Rate,0)
		FROM	#ChargeRate t
		LEFT JOIN cte u ON t.PartyID = u.PartyID AND t.ProductID = u.ProductID AND u.ChargeType = 10
		LEFT JOIN cte u1 ON t.PartyID = u1.PartyID AND t.ProductID = u1.ProductID AND u1.ChargeType = 11
		WHERE t.ProductID = 39
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 59)
	BEGIN
		;WITH cte AS
		(
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.ChargeType
			FROM (	SELECT DISTINCT r.PartyID, r.ProductID, r.DI_Rate, r.ChargeType
				FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'GDG', 'OA') r 
				WHERE r.ChargeType IN (9, 10, 11)
			 ) r
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
		)
		UPDATE t
		SET		t.ChargeRate09 =  ISNULL(u2.DI_Rate,0),
				t.ChargeRate10 = ISNULL(u.DI_Rate,0),
				t.ChargeRate11 = ISNULL(u1.DI_Rate,0)
		FROM	#ChargeRate t
		LEFT JOIN cte u ON t.PartyID = u.PartyID AND t.ProductID = u.ProductID AND u.ChargeType = 10
		LEFT JOIN cte u1 ON t.PartyID = u1.PartyID AND t.ProductID = u1.ProductID AND u1.ChargeType = 11
		LEFT JOIN cte u2 ON t.PartyID = u2.PartyID AND t.ProductID = u2.ProductID AND u2.ChargeType = 9
		WHERE t.ProductID = 59
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 21)
	BEGIN
		-- ChargeRate
		INSERT INTO #ChargeRate(ChargeID,PartyID, LicenseeID,isDeposit, ProductID, Fromdate, Todate, Rate, ChargeRate11, AB_ServiceCharge)
		SELECT ci.ChargeID, ci.PartyId, ci.LicenseeID, ci.IsDeposit, 21 AS ProductID,
			CASE WHEN ci.isDeposit=1 AND ci.FromDate <= dc.FromDate THEN dc.FromDate
					WHEN ci.isDeposit=0 AND ci.FromDate <= cc.FromDate THEN cc.FromDate
					ELSE ci.FromDate END,
			CASE WHEN ci.isDeposit=1 AND ci.Todate >= dc.ToDate THEN dc.ToDate
					WHEN ci.isDeposit=0 AND ci.Todate >= cc.ToDate THEN cc.ToDate
					ELSE ci.ToDate END,
			CASE WHEN ci.isDeposit = 0 THEN 0 ELSE  ci.DI_Rate END,
			ISNULL(ci.DI_Rate * cc.Rate, 0),
			ISNULL(CASE WHEN ci.isDeposit=1 THEN dc.Rate ELSE ci.DI_Rate END,0)
		FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate,@ToDate,'AB','OA',1) ci
		LEFT JOIN dbo.OAS_ChargeInfo dc WITH(NOLOCK) ON
			dc.FromParty = 1 AND
			dc.ToParty = @Allbet AND
			dc.ProductID = ci.ProductID AND
			dc.ToDate >= ci.FromDate AND
			dc.FromDate <= ci.Todate AND
			dc.ChargeType = 9
		LEFT JOIN dbo.OAS_ChargeInfo cc WITH(NOLOCK) ON
			cc.FromParty = ci.PartyID AND
			cc.ProductID = ci.ProductID AND
			cc.ToDate >= ci.FromDate AND
			cc.FromDate <= ci.Todate AND
			cc.ChargeType = 11

		INSERT INTO @PlayCurrencySettings
		SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate
		FROM OPENQUERY(DBACC,'SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType=211')
	END

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 25)
	BEGIN
		INSERT INTO #ChargeRate(ChargeID, PartyID, LicenseeID, isDeposit,ProductID, CashoutCommissionRate, IncomeOnBBRate, Fromdate, Todate )

		SELECT DISTINCT a.ChargeID, PartyID, LicenseeID,  isDeposit, a.ProductID, a.DI_Rate, ci.Rate, 
			CASE WHEN a.FromDate >= ci.FromDate THEN a.FromDate ELSE ci.FromDate END AS FromDate,
			CASE WHEN a.ToDate < ci.ToDate THEN a.ToDate ELSE ci.ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'CO', 'OA', 1) a
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON a.ChargeID = c.ChargeID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
				ON c.ToParty = ci.FromParty AND a.ProductID = ci.ProductID
					AND ((ci.FromDate BETWEEN a.FromDate AND a.ToDate) OR (ci.ToDate BETWEEN a.FromDate AND a.ToDate) OR (ci.FromDate<a.FromDate AND a.ToDate < ci.ToDate))
		WHERE ci.ChargeType != 8

		INSERT INTO @SharingCharge(PartyId, ProductID, FromDate, ToDate, Rate)
		SELECT c.FromParty,
				c.ProductID,
			CASE WHEN c.FromDate > @ToDate THEN @FromDate ELSE c.FromDate END,
			CASE WHEN c.FromDate > @ToDate THEN @ToDate ELSE c.ToDate END,
			CASE WHEN c.FromDate > @ToDate THEN 0 ELSE c.Rate END
		FROM bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK)
		WHERE c.ProductID = 25 AND c.ChargeType = 8
		
	END

	-- Handle date3rd for NG
	UPDATE #ChargeRate
	SET Fromdate3rd = Fromdate,
		Todate3rd	= ToDate
	WHERE ProductID IN (2, 8, 28)

	UPDATE #ChargeRate
	SET Fromdate3rd = Fromdate,
		Todate3rd	= ToDate
	WHERE ProductID IN (5,27) AND isDeposit = 0

	;WITH c AS 
	(
		SELECT DISTINCT PartyID, DI_Rate FROM  bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'VS', 'OA') c
	)
	UPDATE t
	SET  t.Rate3rd = c.DI_Rate
	FROM #ChargeRate t
	INNER JOIN  c ON t.PartyID = c.PartyID
	WHERE t.ProductID = 5

	-- Muay Thai trial setting
	INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
	SELECT ChargeID, PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, 0,  Fromdate, Todate
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 0)
	WHERE ChargeID = 0

	DELETE #ChargeRate
	WHERE (	PartyID NOT IN (SELECT z.PartyId FROM @PartyIdInput z) 
			AND ProductID NOT IN (SELECT t.ProductID FROM @productDataView t)
		 ) OR LicenseeID IS NULL
	--- End Get 3rd for special products

	-- Get Min-Max Site support Index seek condition
	SELECT @MinSite = MIN(LicenseeId), @MaxSite = MAX(LicenseeID) FROM #ChargeRate x
	WHERE x.ProductID IN (SELECT z.ProductID FROM @bettypeExtraGMT z)

	IF EXISTS (SELECT 1 FROM @productDataView WHERE ProductID = 65)
	BEGIN
		INSERT INTO #3rdRatePPL (PartyId, ProductID, FromDate, ToDate, CurrencyId, MinAmount, MaxAmount, Rate)
		SELECT DISTINCT p.PartyId, r.ProductID, r.FromDate, r.ToDate, c.BaseCurrencyId, c.MinAmount - CASE WHEN c.MinAmount = 0 THEN 0 ELSE 1 END, c.MaxAmount, c.Rate
		FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'PPL', 'OA') r
		INNER JOIN #PartyList p ON p.ParentId = r.PartyId
		INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON r.ChargeId = c.ChargeId

		INSERT INTO @BaseCurrencies(ExchangeId, BaseCurrencyName)
		EXEC bodb_licensee.dbo.LA_SelBaseCurrency

		INSERT INTO @BaseCurrencyRate (ExchangeId, ExchangeDate, BaseCurrencyName, Rate)
		SELECT e.ExchangeId, e.ExchangeDate, bc.BaseCurrencyName, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.BaseCurrencyName) e

		-- Update PayToSupplier base on Licensee WL
		SELECT TOP 1 @CurrencyId = CurrencyId FROM #3rdRatePPL WHERE CurrencyId IS NOT NULL

		IF @CurrencyId IS NULL
			SELECT @CurrencyId = ExchangeId FROM @BaseCurrencies WHERE BaseCurrencyName = @BaseCurrencyName
	
		SELECT @CurrencyName = Code FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @CurrencyId

		UPDATE #3rdRatePPL SET CurrencyId = @CurrencyId WHERE CurrencyId IS NULL
		UPDATE #3rdRatePPL SET MinAmount = 0, MaxAmount = 10000000000000 WHERE MinAmount IS NULL OR MaxAmount IS NULL
	END

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH'
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code 
														END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	CREATE CLUSTERED INDEX cix_#Exchange ON #Exchange(ExchangeID, exchangedate)

	INSERT INTO @AllbetBettype (Bettype)
	SELECT	DISTINCT la.Bettype
	FROM	LA_f_BettypeProductMapping(0,'AB') la

	INSERT INTO #AllbetPlayCurrency (SiteId, MemberCurrency, PlayCurrency, FromDate, ToDate, Bettype)
	SELECT	  s.SiteId, pc.MemberCurrency, pc.PlayCurrency, pc.FromDate, pc.ToDate, z.Bettype
	FROM	  dbo.view_site_list s WITH(NOLOCK) 
	LEFT JOIN @PlayCurrencySettings pc ON s.IbcSiteID = pc.SiteId
	CROSS APPLy (SELECT z.Bettype FROM @AllbetBettype z) z
	WHERE s.SiteID IN (SELECT DISTINCT z.LicenseeID FROM #ChargeRate z WHERE z.ProductID = 21)				
									
	CREATE CLUSTERED INDEX cix_#AllbetPlayCurrency ON #AllbetPlayCurrency(SiteId)

	-- Get ExtraAmont Bettype
	INSERT INTO @ExtraAmtGroupBettype(ProductID, TypeId, Bettype)
	SELECT ProductID, TypeId, Bettype FROM dbo.LA_f_GroupBettype()

	INSERT INTO @ExtraAmtProduct(ProductID)
	SELECT DISTINCT ProductID FROM dbo.LA_f_GroupBettype() WHERE TypeID IN (2,3)
	---- End 
	
	IF @Timezone = 1 -- GMT -4
	BEGIN
		;WITH cte_Summary AS(
			SELECT b.RptDate, b.RptDate3rd, b.SiteId, b.BetTypeId, b.CurrencyId,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.BetCount END) AS TotalTrans,
				-SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.Winloss END) AS LicenseeWinloss,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
				SUM(b.ValidBetAmount) AS ValidBetAmount,
				SUM(CASE WHEN e.TypeID = 1 THEN -b.Winloss ELSE 0 END) AS CompanyTipShare,
				SUM(CASE WHEN e.TypeID = 3 THEN b.Winloss ELSE 0 END)  AS JackpotPrize,
				SUM(CASE WHEN e.TypeID = 2 THEN ProgressiveContribution ELSE 0 END)  AS FullContribution,
				SUM(CASE WHEN e.TypeID = 2 THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
				SUM(CASE WHEN e.TypeID IN (4,5,6,8) THEN b.Winloss ELSE 0 END) Promotion
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			LEFT JOIN @ExtraAmtGroupBettype e ON b.BetTypeId = e.Bettype
			WHERE b.RptDate BETWEEN @FDATE AND @TDATE
				AND b.RptDate3rd BETWEEN @FDATE_GMT AND @TDATE_GMT
				AND b.SiteId BETWEEN @MinSite AND @MaxSite -- Seek condition
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20  
			GROUP BY b.RptDate, b.RptDate3rd, b.SiteId, b.BetTypeId, b.CurrencyId
			UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,ProductID,isDeposit,RollingComm,NetWinLoss,CompanyTipShare,RoyaltyFee,JackpotPrize,LicenseeContribution,FullContribution,LicenseeChargeRate,ServiceChargeOriginal,RebateCommissionOriginal, Playcurrency, Promotion)
		SELECT ci.PartyId,
			b.RptDate as Winlostdate,
			b.CurrencyId,
			0,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			SUM(b.LicenseeWinloss) AS LicenseeWinloss,
			SUM((b.LicenseeWinloss - b.LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - Promotion) AS LicensingFee,
			SUM(CASE WHEN bt.ProductID IN (70, 76, 80) THEN (LicenseeWinloss - (b.ValidBetAmount * ci.ChargeRate11)) * ISNULL(ci_3rd.Rate3rd,0)
					 WHEN bt.ProductID = 32 THEN (b.LicenseeWinloss - b.FullContribution) * ISNULL(ci_3rd.Rate3rd,0)
				ELSE (b.LicenseeWinloss - b.FullContribution) * ISNULL(ci_3rd.Rate3rd,0) - b.Promotion END
				) AS PayToSupplier,
			bt.ProductID,
			ci.isDeposit,
			SUM(b.ValidBetAmount * ci.ChargeRate11) AS RollingComm,
			SUM(b.LicenseeWinloss - b.ValidBetAmount * ci.ChargeRate11) AS NetWinLoss,
			SUM(b.CompanyTipShare * ci.ChargeRate12 ) AS CompanyTipShare,
			SUM((b.LicenseeWinloss - b.ValidBetAmount * ci.ChargeRate11) * ci.ChargeRate10) AS RoyaltyFee,
			SUM(JackpotPrize),
			SUM(LicenseeContribution),
			SUM(FullContribution),
			SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
			SUM(b.LicenseeWinloss * ci.AB_ServiceCharge) AS ServiceChargeOriginal,
			SUM(b.ValidBetAmount * ci.ChargeRate11) AS RebateCommissionOriginal,
			ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency,
			SUM(Promotion)
		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN @bettypeExtraGMT bt ON b.BetTypeId = bt.bettype
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND bt.ProductID = ci.ProductID AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN #ChargeRate ci_3rd ON b.SiteID = ci_3rd.LicenseeId AND bt.ProductID = ci_3rd.ProductID AND b.RptDate BETWEEN ci_3rd.FromDate3rd AND ci_3rd.Todate3rd
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
			LEFT JOIN #AllbetPlayCurrency pc ON (
													b.SiteID = pc.SiteId AND
													b.BetTypeId = pc.Bettype AND
													b.CurrencyId = pc.MemberCurrency AND
													b.rptDate BETWEEN pc.FromDate AND pc.ToDate
												)
		GROUP BY ci.PartyId, b.RptDate, b.CurrencyId, bt.ProductID, ci.isDeposit, ISNULL(pc.PlayCurrency, b.CurrencyId)

		-- Get data 
		;WITH cte_Summary AS(
			SELECT
				b.SiteID,
				b.rptDate  AS Winlostdate,
				b.CurrencyId,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.BetCount END) AS TotalTrans,
				-SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE  b.MemberWL END) AS LicenseeWinloss,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.MemberWL END) AS CustomerWinLoss,
				SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount,
				b.ProductID,
				SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(ci.ChargeRate11, 0)) AS RollingComm,
				SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
				SUM(ISNULL(b.WinPrizeAmount,0)) CBPrize,
				SUM(ISNULL(b.CashOutAmount,0)) CashOut,
				SUM(ISNULL(b.BuyBackAmount,0)) CashInAmount,
				SUM(ISNULL(b.Turnover,0)) Turnover,
				SUM(ISNULL(b.CommissionA,0)) CommissionA,
				SUM(ISNULL(b.CommissionP,0)) CommissionP,
				SUM(CASE WHEN e.TypeID IN (4,5,6,8) THEN b.MemberWL ELSE 0 END) Promotion,
				SUM(CASE WHEN e.TypeID = 3 THEN b.MemberWL ELSE 0 END)  AS JackpotPrize,
				SUM(CASE WHEN e.TypeID = 2 THEN b.ExtraAmount ELSE 0 END)  AS FullContribution,
				SUM(CASE WHEN e.TypeID = 2 THEN -b.GrossWL ELSE 0 END) AS LicenseeContribution
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND  b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
				INNER JOIN @productDataView p ON b.ProductID = p.ProductID
				LEFT JOIN @ExtraAmtGroupBettype e ON b.BetType = e.Bettype
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20  AND b.CustomerCategory NOT IN (27,28)
				AND p.isRptBettingSource = 0 
				AND p.isRptBettingBySportSource = 0
				AND p.isSupportGMT0 = 0 
				AND p.isSupportGMT8 = 0
				AND p.isRptLicCashoutSummarySource = 0
			GROUP BY b.SiteID, b.rptDate, b.CurrencyId, b.ProductID
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,ProductID, TurnoverForCommision, CBPrize, CashOut, CashInAmount, Turnover, Promotion, LicenseeChargeRate, isDeposit, JackpotPrize, FullContribution, LicenseeContribution)
		SELECT ci.PartyId,
			b.Winlostdate as Winlostdate,
			b.CurrencyId,
			0,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			SUM(b.LicenseeWinloss) AS LicenseeWinloss,
			SUM(CASE WHEN b.ProductID = 31 THEN CASE WHEN @FromDate < @ExchangeCutoffDate THEN b.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate) - (b.CommissionA + b.CommissionP) ELSE -(b.CustomerWinLoss + b.CommissionP) * ISNULL(cr.Rate, ci.Rate) END
				 ELSE b.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate) 
				END) AS LicensingFee,
			SUM(CASE WHEN b.ProductID = 59  THEN (b.LicenseeWinloss - b.RollingComm) * CASE WHEN ci.isDeposit = 1 THEN ci.ChargeRate09 ELSE ci.ChargeRate10 END
					 WHEN b.ProductID = 10  THEN 0
					 WHEN b.ProductID = 31  THEN  CASE WHEN @FromDate < @ExchangeCutoffDate THEN  b.LicenseeWinloss  * ISNULL(ci_3rd.Rate3rd,0) - (b.CommissionA + b.CommissionP) ELSE -(b.CustomerWinLoss + b.CommissionP)  * ISNULL(ci_3rd.Rate3rd,0) END
					 WHEN b.ProductID = 80 THEN (LicenseeWinloss - (b.ValidBetAmount * ci.ChargeRate11)) * ISNULL(ci_3rd.Rate3rd,0)
					 WHEN b.ProductID IN (3, 6, 38, 66, 63, 72) THEN 0 -- Inhouse products
					 ELSE b.LicenseeWinloss  * ISNULL(ci_3rd.Rate3rd,0) - b.Promotion
				END) AS PayToSupplier,
			b.ProductID,
			SUM(TurnoverForCommision), 
			SUM(CBPrize), 
			SUM(CashOut), 
			SUM(CashInAmount),
			SUM(Turnover),
			SUM(Promotion),
			SUM((LicenseeWinloss- LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
			ci.isDeposit,
			SUM(b.JackpotPrize),
			SUM(b.FullContribution),
			SUM(b.LicenseeContribution)
		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN #ChargeRate ci_3rd ON b.SiteID = ci_3rd.LicenseeId AND  b.ProductID = ci_3rd.ProductID AND b.Winlostdate BETWEEN ci_3rd.FromDate3rd AND ci_3rd.Todate3rd
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
		GROUP BY b.Winlostdate, ci.PartyId, b.CurrencyId, b.ProductID, ci.isDeposit

		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'CO')
		BEGIN
			INSERT INTO #TempData(PartyID, WinlostDate, ProductID, CurrencyId, BuyBackAmountTotal, TicketsPayout, CashoutCommission, IncomeOnBB)
			SELECT p.PartyId, b.Winlostdate, b.ProductID, b.Currency,
				SUM(b.BuyBackAmt + b.BABuyBackAmt) AS BuyBackAmountTotal,
				SUM(b.TicketPayout) AS TicketsPayout,
				SUM((b.BuyBackAmt + b.BABuyBackAmt) * p.CashoutCommissionRate) AS CashoutCommission,
				SUM((b.BuyBackAmt + b.BABuyBackAmt) * p.IncomeOnBBRate) AS IncomeOnBB
	
			FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
				INNER JOIN #ChargeRate p ON b.SiteId = p.LicenseeID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate AND p.ProductID = 25
			WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate
				AND b.Currency <> 20
				AND b.ProductID = 25
				AND b.RoleID = 1
			GROUP BY p.PartyId,b.ProductID, b.Winlostdate, b.Currency

			UPDATE  d
			SET d.IncomeOnProfitSharing = (d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission) * c.Rate,
				d.AmtDueToOnBB = d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission - d.IncomeOnBB,
				d.AmtDueToOnProfitSharing = (d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission) * c.Rate,
				d.LicensingFee = d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission
			FROM #TempData d
			INNER JOIN #PartyList p ON d.PartyID = p.PartyId
			LEFT JOIN @SharingCharge c ON p.ParentId = c.PartyId AND c.ProductID= d.ProductID AND d.WinlostDate BETWEEN c.FromDate AND c.ToDate
			WHERE d.ProductID = 25
			
		END

		IF EXISTS(SELECT 1 FROM @productDataView WHERE isRptBettingSource = 1)
		BEGIN
			SELECT @ProductRptbettingSource = COALESCE(@ProductRptbettingSource + ',', '') + CONVERT(VARCHAR(10), ProductCode) FROM @productDataView WHERE isRptBettingSource = 1
		
			;WITH la AS 
			(
				SELECT	la.Bettype, la.ProductID
				FROM	LA_f_BettypeProductMapping(0,@ProductRptbettingSource) la
			), ma AS
			(
				SELECT DISTINCT ma.BetType, ma.SubProduct FROM bodb02.dbo.SportBettypeMatrix ma (NOLOCK)
				WHERE ma.ProductID IN (SELECT x.ProductID FROM @productDataView x WHERE x.isRptBettingSource = 1)
			)
			INSERT INTO @bettype (Bettype, ProductID, SubProduct)
			SELECT	la.Bettype, la.ProductID,  ma.SubProduct
			FROM	 la
			LEFT JOIN ma ON la.Bettype = ma.BetType 

			IF EXISTS (SELECT 1 FROM @productDataView WHERE isRptBettingSource = 1 AND ProductCode = 'SB_BetBuilder')
			BEGIN
				INSERT INTO @bettype(Bettype, ProductID)
				SELECT 38 AS Bettype, 0 -- -1: BetBuilder
			END

			SELECT @MinSite_rpt_Betting = MIN(LicenseeId) , @MaxSite_rpt_Betting = MAX(LicenseeId)
			FROM #ChargeRate
			WHERE ProductID IN (SELECT z.ProductID FROM @bettype z)

			SELECT @MinBettype_rpt_Betting = MIN(Bettype) , @MaxBettype_rpt_Betting = MAX(Bettype)
			FROM @bettype
			-- End
			
			;WITH cte_Data AS 
			(
				SELECT	b.SiteID, 
						b.rptDate as Winlostdate, 
						b.CurrencyId, 
						bt.ProductID, 
						bt.SubProduct,
						SUM(ISNULL(b.WinLossE, 0) +  ISNULL(b.CommissionE, 0)) AS ExtraPT,
						SUM(b.BetCount)		AS TotalTrans,
						SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN 0 ELSE b.WinLoss END) AS CustomerWinLoss,
						SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN 0 
								 WHEN bt.ProductID = 23 THEN -(b.WinLoss + b.WinLossS + b.WinLossM + b.WinLossA + b.CommissionS)
								 ELSE -b.WinLoss END)	AS LicenseeWinloss,
						SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN b.WinLoss ELSE 0 END) AS Bonus,
						SUM(b.WinLoss) CustomerWinLossSB ,
						0 CustomerWinLossBA ,
						0 CommissionA,
						SUM(CASE WHEN ci.ProductID = 0 AND  ci.isDeposit = 1 THEN	0 ELSE b.CommissionS END) AS CommissionS,
						SUM(CASE WHEN ci.ProductID = 0 AND  ci.isDeposit = 1 THEN (-b.WinLoss * ISNULL(cr.Rate, ci.Rate))
						ELSE -(b.Winloss + b.WinLossA + b.WinLossM + b.WinLossS + b.CommissionS) END) LicensingFee,
						SUM(CASE WHEN ci.ProductID = 23 THEN  -(b.WinLoss + b.WinLossS + b.WinLossM + b.WinLossA + b.CommissionS) * ISNULL(ci_3rd.Rate3rd,0) ELSE 0 END) AS PaytoSupplier -- NG2 PaytoSupplier
				FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @bettype bt		ON b.Bettype = bt.Bettype
					INNER JOIN #ChargeRate ci	ON b.SiteID = ci.LicenseeId AND bt.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate 
					LEFT JOIN #ChargeRate ci_3rd	ON b.SiteID = ci_3rd.LicenseeId AND bt.ProductID = ci_3rd.ProductID AND b.rptDate BETWEEN ci_3rd.FromDate3rd AND ci_3rd.ToDate3rd 
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
												
				WHERE b.rptDate BETWEEN @FromDate AND @ToDate
						AND b.SiteID BETWEEN @MinSite_rpt_Betting AND @MaxSite_rpt_Betting
						AND b.Bettype BETWEEN @MinBettype_rpt_Betting AND @MaxBettype_rpt_Betting
						AND b.Status NOT IN (-1, 101, 102, 103) 
						AND b.CurrencyId <> 20 
						AND b.CustomerCategory NOT IN (27,28)
				GROUP BY b.SiteID, b.rptDate, b.CurrencyId, bt.ProductID, bt.SubProduct

			UNION ALL
			SELECT	b.SiteID, 
					b.rptDate as Winlostdate, 
					b.CurrencyId, 
					0 ProductID, 
					NULL AS SubProduct,
					0 ExtraPT,
					SUM(b.BetCount)	AS TotalTrans,
					0	AS CustomerWinLoss,
					0	AS LicenseeWinloss,
					0	AS Bonus,
					0	AS CustomerWinLossSB ,
					SUM(b.WinLoss) CustomerWinLossBA ,
					SUM(CommissionA) CommissionA,
					0	AS CommissionS,
					0	AS LicensingFee,
					0	AS PaytoSupplier
				FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH (NOLOCK)
				WHERE b.rptDate BETWEEN @FromDate AND @ToDate
						AND b.SiteID BETWEEN @MinSite_rpt_Betting AND @MaxSite_rpt_Betting
						AND b.Bettype = @BetBuilderBetTypeId
						AND b.Status NOT IN (-1, 101, 102, 103) 
						AND b.CurrencyId <> 20 
						AND b.CustomerCategory NOT IN (27,28)
				GROUP BY b.SiteID, b.rptDate, b.CurrencyId
			)
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,Promotion,ProductID,CustomerWinLossSB,CustomerWinLossBA,CommissionA,CommissionS,isDeposit, LicenseeChargeRate)
			SELECT ci.PartyID, r.Winlostdate, r.CurrencyID,
					SUM(r.ExtraPT),
					SUM(r.TotalTrans), 
					SUM(r.CustomerWinLoss), 
					SUM(r.LicenseeWinloss), 
					SUM(CASE WHEN r.ProductID = 23 THEN 0 
							 WHEN r.ProductID = 33 AND ci.isDeposit = 1 THEN (r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate))
							 WHEN r.ProductID = 22 THEN r.LicenseeWinloss * ISNULL(cr.Rate, ci.Rate)
							 WHEN r.ProductID = 2 AND ci.isDeposit = 0  THEN r.LicensingFee
							 WHEN r.ProductID = 2 AND ci.isDeposit = 1  THEN r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate)
							 WHEN r.ProductID = 34 AND ci.isDeposit = 1 THEN (r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate))
							 WHEN r.ProductID = 0 THEN r.LicensingFee
							 ELSE 0 END) AS LicensingFee,
					SUM(CASE WHEN r.ProductID = 2 AND ci.isDeposit = 0 THEN (r.LicensingFee - CASE WHEN r.SiteID IN (1487/*IBCIndo*/, 1547/*76666b*/) THEN ExtraPT ELSE 0 END) * ISNULL(ci_3rd.Rate3rd,0)
							 WHEN r.ProductID = 2 AND ci.isDeposit = 1 THEN r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate) * ISNULL(ci_3rd.Rate3rd,0)
							 WHEN r.ProductID = 22 THEN r.LicenseeWinloss *  CASE  WHEN ci.IsDeposit = 1 THEN (CASE WHEN r.SubProduct = 'Blueprint' THEN @VB_depositBlueprint3rd ELSE @VB_depositNotBlueprint3rd END)
																		     ELSE CASE WHEN r.SubProduct = 'Blueprint' THEN @VB_creditBlueprint3rd ELSE @VB_creditNotBlueprint3rd END END 
							 WHEN r.ProductID = 23 THEN r.PayToSupplier
							 WHEN r.ProductID = 34 THEN r.LicenseeWinloss * (CASE WHEN r.SubProduct = 'Mini Game' THEN @CC_MidasRate3rd ELSE @CC_NormalRate3rd END) - r.Bonus
							 ELSE 0 END) AS PayToSupplier,
					SUM(Bonus),
					CASE WHEN r.ProductID = 0 THEN -1 ELSE r.ProductID END ProductID,
					SUM(CustomerWinLossSB),
					SUM(CustomerWinLossBA),
					SUM(CommissionA),
					SUM(CommissionS),
					ci.isDeposit,
					SUM(CASE WHEN r.ProductID = 23 THEN 0 
							 WHEN r.ProductID = 33 AND ci.isDeposit = 1 THEN (r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate))
							 WHEN r.ProductID = 22 THEN r.LicenseeWinloss * ISNULL(cr.Rate, ci.Rate)
							 WHEN r.ProductID = 2 AND ci.isDeposit = 0  THEN r.LicensingFee
							 WHEN r.ProductID = 2 AND ci.isDeposit = 1  THEN r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate)
							 WHEN r.ProductID = 34 AND ci.isDeposit = 1 THEN (r.LicenseeWinloss  * ISNULL(cr.Rate, ci.Rate))
							 WHEN r.ProductID = 0 THEN r.LicensingFee
							 ELSE 0 END) AS LicenseeChargeRate
			FROM cte_Data r
				INNER JOIN #ChargeRate ci	ON r.SiteID = ci.LicenseeId AND r.ProductID = ci.ProductID AND r.Winlostdate BETWEEN ci.FromDate AND ci.ToDate 
				LEFT JOIN #ChargeRate ci_3rd ON r.SiteID = ci_3rd.LicenseeId AND r.ProductID = ci_3rd.ProductID AND r.Winlostdate BETWEEN ci_3rd.FromDate3rd AND ci_3rd.ToDate3rd 
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = r.CurrencyId
			GROUP BY ci.PartyID, r.Winlostdate, r.CurrencyId, r.ProductID, ci.isDeposit
		END

		IF EXISTS(SELECT 1 FROM @productDataView WHERE isRptBettingBySportSource = 1)
		BEGIN
			INSERT INTO #TempData (PartyId, Winlostdate, CurrencyId, TotalTrans, CustomerWinLoss, WLShare, LicComm, CommShare, LicensingFee, ProductID, isDeposit)
			SELECT
					p.PartyId,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.AdjustedCustomerWL, 0)) MemberWL,
					SUM(ISNULL(b.AdjustedCustomerWL, 0) * (- @ShareRate)) WLShare,
					SUM(ISNULL(b.AdjustedCommissionS, 0)) LicComm,
					SUM(ISNULL(b.AdjustedCommShare, 0)) CommShare,
					SUM(CASE WHEN p.IsDeposit = 0
							THEN ISNULL(b.AdjustedLicenseeWL, 0)
							ELSE ISNULL(-b.AdjustedCustomerWL, 0) * ISNULL(cr.Rate, p.Rate)
						END) AmtLicensee,
					b.ProductID,
					p.isDeposit
			FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
					INNER JOIN #ChargeRate p ON b.ProductID = p.ProductID
													AND b.SiteID = p.LicenseeId
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN (27, 28)
					AND b.SportType = 44 -- MuayThai
			GROUP BY b.rptdate, p.PartyId, b.CurrencyID,  b.ProductID, p.isDeposit
			
		END
	END

	IF @Timezone IN (0,2) 
	BEGIN
		;WITH cte_Summary AS(
			SELECT b.RptDate, b.RptDate3rd, b.SiteId, b.BetTypeId, b.CurrencyId,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.BetCount END) AS TotalTrans,
				-SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.Winloss END) AS LicenseeWinloss,
				SUM(CASE WHEN e.TypeID IN (1,2,3,4,5,6,8) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
				SUM(b.ValidBetAmount) AS ValidBetAmount,
				SUM(CASE WHEN e.TypeID = 1 THEN -b.Winloss ELSE 0 END) AS CompanyTipShare,
				SUM(CASE WHEN e.TypeID = 3 THEN b.Winloss ELSE 0 END)  AS JackpotPrize,
				SUM(CASE WHEN e.TypeID = 2 THEN ProgressiveContribution ELSE 0 END)  AS FullContribution,
				SUM(CASE WHEN e.TypeID = 2 THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
				SUM(CASE WHEN e.TypeID IN (4,5,6,8) THEN b.Winloss ELSE 0 END) Promotion
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			LEFT JOIN @ExtraAmtGroupBettype e ON b.BetTypeId = e.Bettype
			WHERE  b.RptDate BETWEEN @FDATE_GMT AND @TDATE_GMT
				AND b.RptDate3rd BETWEEN @FDATE AND @TDATE
				AND b.SiteId BETWEEN @MinSite AND @MaxSite -- Seek condition
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20  
			GROUP BY b.RptDate, b.RptDate3rd, b.SiteId, b.BetTypeId, b.CurrencyId
			UNION SELECT NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,ProductID,isDeposit,RollingComm,NetWinLoss,CompanyTipShare,RoyaltyFee,JackpotPrize,LicenseeContribution,FullContribution,LicenseeChargeRate,ServiceChargeOriginal,RebateCommissionOriginal, Playcurrency, Promotion)
		SELECT ci.PartyId,
			b.RptDate3rd as Winlostdate,
			b.CurrencyId,
			0,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			SUM(b.LicenseeWinloss) AS LicenseeWinloss,
			SUM((b.LicenseeWinloss - b.LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - Promotion) AS LicensingFee,
			SUM(CASE WHEN bt.ProductID IN (70,76) THEN (LicenseeWinloss - (b.ValidBetAmount * ci.ChargeRate11)) * ISNULL(ci_3rd.Rate3rd,0)
					WHEN bt.ProductID = 32 THEN (b.LicenseeWinloss - b.FullContribution) * ISNULL(ci_3rd.Rate3rd,0)
				ELSE (b.LicenseeWinloss - b.FullContribution) * ISNULL(ci_3rd.Rate3rd,0) - b.Promotion END
				) AS PayToSupplier,
			bt.ProductID,
			ci.isDeposit,
			SUM(b.ValidBetAmount * ci.ChargeRate11) AS RollingComm,
			SUM(b.LicenseeWinloss - b.ValidBetAmount * ci.ChargeRate11) AS NetWinLoss,
			SUM(b.CompanyTipShare * ci.ChargeRate12 ) AS CompanyTipShare,
			SUM((b.LicenseeWinloss - b.ValidBetAmount * ci.ChargeRate11) * ci.ChargeRate10) AS RoyaltyFee,
			SUM(JackpotPrize),
			SUM(LicenseeContribution),
			SUM(FullContribution),
			SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
			SUM(b.LicenseeWinloss * ci.AB_ServiceCharge) AS ServiceChargeOriginal,
			SUM(b.ValidBetAmount * ci.ChargeRate11) AS RebateCommissionOriginal,
			ISNULL(pc.PlayCurrency, b.CurrencyId) AS PlayCurrency,
			SUM(Promotion)
		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN @bettypeExtraGMT bt ON b.BetTypeId = bt.bettype
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND bt.ProductID = ci.ProductID AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN #ChargeRate ci_3rd ON b.SiteID = ci_3rd.LicenseeId AND bt.ProductID = ci_3rd.ProductID AND b.RptDate3rd BETWEEN ci_3rd.FromDate3rd AND ci_3rd.Todate3rd
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
			LEFT JOIN #AllbetPlayCurrency pc ON (
													b.SiteID = pc.SiteId AND
													b.BetTypeId = pc.Bettype AND
													b.CurrencyId = pc.MemberCurrency AND
													b.rptDate BETWEEN pc.FromDate AND pc.ToDate
												)
		GROUP BY ci.PartyId, b.RptDate3rd, b.CurrencyId, bt.ProductID, ci.isDeposit, ISNULL(pc.PlayCurrency, b.CurrencyId)
	END


	BEGIN -- Continue process #TempData based on each special products
		IF EXISTS(SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'AGC')
		BEGIN
			UPDATE td
			SET td.ApplyValue =  CASE WHEN pa.PartyId = 1 -- group Oneworks
									THEN -td.CustomerWinLoss * ec.BaseCurrencyRate
									ELSE -td.CustomerWinLoss * eu.BaseCurrencyRate END,
				td.ParentId	  = pa.PartyId
			FROM #TempData td
			INNER JOIN #PartyList p ON td.PartyId = p.PartyID AND p.ParentId > 0		-- party
			INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId AND pa.ParentId = 0		-- billing group
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.Winlostdate
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD') eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.Winlostdate
			WHERE td.ProductID = 10

			INSERT INTO @ApplyRange (ParentId, SumApplyValue)
			SELECT ParentId, SUM(ApplyValue)
			FROM	#TempData
			WHERE	ProductID = 10
			GROUP BY ParentId

			UPDATE @ApplyRange
			SET ApplyRate = CASE WHEN @FromDate >= '2023-10-01' THEN 0.07 -- Apply for all groups
							ELSE
									CASE WHEN ParentId = 1 -- Oneworks
									THEN CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
									ELSE CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END 
									END
							END

			UPDATE r
			SET r.PayToSupplier = a.ApplyRate * r.LicenseeWinLoss + r.FullContribution - r.JackpotPrize - r.Promotion
			FROM #TempData r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
			WHERE r.ProductID = 10
		END

		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SAG')
		BEGIN
			--Region Update deposit's pay to supplier
			/*  To specific, 5% If Σ OneWorks Licensee Gross WL >= 10M CNY
				To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY */

			INSERT INTO @SAG_ApplyRange (ParentId, SumApplyValue)
			SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END, SUM(-d.CustomerWinLoss * ec.BaseCurrencyRate)
			FROM #TempData d
			INNER JOIN #PartyList p ON d.PartyId = p.PartyId
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON d.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = d.Winlostdate
			WHERE ISNULL(d.IsDeposit, 0) = 1 AND d.ProductID = 39
			GROUP BY CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END

			UPDATE @SAG_ApplyRange
			SET ApplyRate = CASE WHEN (ParentId = @OneWorks AND SumApplyValue >= 10000000)
										OR (ParentId = @BopingAndZelianta AND SumApplyValue >= 10000000)
										THEN 0.05
										ELSE 0.06 
							END

			;WITH cte_SelectedDepositSettings AS(
				SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END AS ParentId,
							d.PartyId
				FROM #TempData d
				INNER JOIN #PartyList p ON d.PartyId = p.PartyId
				WHERE ISNULL(d.IsDeposit, 0) = 1 AND d.ProductID = 39
			)
			UPDATE d
			SET d.RoyaltyFee = a.ApplyRate * (d.NetWinLoss)
			FROM #TempData d
			INNER JOIN cte_SelectedDepositSettings d2 ON d.PartyId = d2.PartyId
			INNER JOIN @SAG_ApplyRange a ON d2.ParentId = a.ParentId
			WHERE  d.ProductID = 39


			UPDATE d 
			SET d.PayToSupplier = d.RoyaltyFee + d.CompanyTipShare
			FROM #TempData d
			WHERE  d.ProductID = 39
			--End-Region Update deposit's pay to supplier
		END

		IF EXISTS (SELECT 1 FROM STRING_SPlit(@ProductCodes,',') WHERE value = 'PP')
		BEGIN
			INSERT INTO @PP_BaseCurrencies(Id, Name)
			EXEC LA_SelBaseCurrency

			-- Region Credit
			INSERT INTO @RateOfCredit(PartyId, ProductID, Rate, MinAmount, MaxAmount, BaseCurrencyId)
			SELECT DISTINCT	ci.FromParty, ci.ProductID , ci.Rate, ci.MinAmount, ci.MaxAmount, ci.BaseCurrencyId
			FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			INNER JOIN #ChargeRate ci2 ON ci.FromParty = ci2.PartyId 
			WHERE ci2.isDeposit = 0 AND ci.ProductID = 32 AND ci2.ProductID =32
			ORDER BY FromParty, MaxAmount DESC

			-- Region TotalAmountOfCreditGroup
			SELECT TOP 1 @CreditBaseCurrencyName = [Name], @CreditBaseCurrencyId = BaseCurrencyId FROM @PP_BaseCurrencies b INNER JOIN @RateOfCredit c ON c.BaseCurrencyId=b.Id

			-- Region: @TotalAmount_BasedOn_CreditBaseCurrencyName
			SELECT @TotalAmount_BasedOn_CreditBaseCurrencyName = SUM((-r.CustomerWinLoss - FullContribution) * e.BaseCurrencyRate)
			FROM #TempData r
			INNER JOIN (SELECT DISTINCT PartyId, ProductID FROM @RateOfCredit) roc ON r.PartyID = roc.PartyId AND r.ProductID = roc.ProductID
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlostdate
			WHERE r.ProductID = 32 AND r.isDeposit = 0
				-- End region: @TotalAmount_BasedOn_CreditBaseCurrencyName
			--Endregion TotalAmountOfCreditGroup

			-- Region Update PayToSupplier for #Result
			;WITH SumByPropressiveAmount AS(
				SELECT  r.PartyId,CurrencyId,Winlostdate,
						SUM(CASE 
							WHEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate) > MaxAmount THEN MaxAmount 
							WHEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate  - MinAmount) > 0 THEN ((r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate - MinAmount)
							WHEN (r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN (r.LicenseeWinloss - r.FullContribution) * e.BaseCurrencyRate 
							ELSE 0 END  * roc.Rate / e.BaseCurrencyRate)  AS ProgressiveAmount
				FROM #TempData r 
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlostdate
				INNER JOIN @RateOfCredit roc ON r.PartyID = roc.PartyID AND r.ProductID = roc.ProductID
				WHERE r.ProductID = 32 AND r.isDeposit = 0
				GROUP BY r.PartyId,CurrencyId,Winlostdate
			)
			UPDATE r
			SET r.PayToSupplier = ProgressiveAmount
			FROM #TempData r
			INNER JOIN SumByPropressiveAmount s ON r.PartyId = s.PartyID AND r.CurrencyId = s.CurrencyId AND r.Winlostdate = s.Winlostdate
			WHERE r.ProductID = 32 AND r.isDeposit = 0
		-- Endregion Update PayToSupplier for #Result
		END

		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'CB')
		BEGIN
			INSERT INTO @CBChargeInfo (PartyID, LicenseeID, DI_Rate, ChargeType, Fromdate, ToDate)
			SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds,@FromDate,@ToDate,'CB','OA',1)
			
			INSERT INTO @CBBaseCurrencies(Id, Name)
			EXEC LA_SelBaseCurrency

			SELECT TOP 1 @CBBaseCurrency = Name FROM @CBBaseCurrencies b INNER JOIN @CBShare c ON c.BaseCurrencyId=b.Id
	
			INSERT INTO @TotalByPeriod(FromDate, Todate, TurnoverForCommision, CashInAmount)
			SELECT 
				s.FromDate, 
				s.ToDate, 
				SUM(td.TurnoverForCommision*e.BaseCurrencyRate),
				SUM(td.CashInAmount*e.BaseCurrencyRate)
			FROM #TempData td
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CBBaseCurrency) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.Winlostdate
			INNER JOIN (SELECT DISTINCT FromDate, ToDate FROM @CBShare) s ON td.Winlostdate BETWEEN s.FromDate AND s.ToDate
			WHERE td.ProductID = 15
			GROUP BY s.FromDate, s.ToDate
		
			INSERT INTO @RateByPeriod(FromDate, ToDate, CommissionRate, CashInShareRate)
			SELECT t.FromDate,t.ToDate,ISNULL(cm.Rate,0),ISNULL(cs.Rate,0)
			FROM @TotalByPeriod t
			LEFT JOIN @CBShare cm ON cm.TypeId = 6  -- Commission share
				AND cm.FromDate = t.FromDate 
				AND cm.ToDate = t.ToDate
				AND t.TurnoverForCommision > cm.MinAmount
				AND t.TurnoverForCommision <= cm.MaxAmount 
			LEFT JOIN @CBShare cs ON cs.TypeId = 7 -- Cash in share
				AND cs.FromDate = t.FromDate
				AND cs.ToDate = t.ToDate
				AND t.CashInAmount > cs.MinAmount
				AND t.CashInAmount <= cs.MaxAmount
			-- end get commissionRate, cashinshareRate for every Period in @CBShare		
	
			UPDATE r
			SET
				PayToSupplier = Turnover - CBPrize - CashOut - (r.TurnoverForCommision * rbp.CommissionRate) - (r.CashInAmount * rbp.CashInShareRate)

			FROM #TempData r
			INNER JOIN @RateByPeriod rbp ON r.Winlostdate BETWEEN rbp.FromDate AND rbp.ToDate	
			WHERE r.ProductID = 15

			UPDATE r
			SET LicensingFee = Turnover - CBPrize - CashOut - (r.TurnoverForCommision * cm.DI_Rate) - (r.CashInAmount * ci.DI_Rate)
			FROM #TempData r
			INNER JOIN @CBChargeInfo AS cm ON cm.PartyID = r.PartyID AND cm.ChargeType = 6 AND (r.Winlostdate BETWEEN cm.FromDate AND cm.ToDate)
			INNER JOIN @CBChargeInfo AS ci ON ci.PartyID = r.PartyID AND ci.ChargeType = 7 AND (r.Winlostdate BETWEEN ci.FromDate AND ci.ToDate)
			WHERE r.ProductID = 15
			-- End Update Commission, CashInShare, AmountDueToColossusBet for #Result
		END
	END

	INSERT INTO #Result (ParentId, ParentName, PartyId, ProductID,TotalTrans,CustomerWinLoss,LicenseeWinLoss,
							LicensingFee,ExtraPT,PayToSupplier,IsKeepNegativeAmount,
							WLShare,LicComm, CommShare,CustomerWinLossSB,CustomerWinLossBA,CommissionA,CommissionS,CompanyTipShare,
							IncomeOnBB,IncomeOnProfitSharing,AmtDueToOnBB,AmtDueToOnProfitSharing,LicenseeChargeRate,JackpotPrize,LicenseeContribution,FullContribution,IsDeposit,Promotion
							)
	SELECT 
		pa.PartyId AS ParentId,
		pa.PartyName AS ParentName,
		td.PartyId,
		td.ProductID,
		SUM(td.TotalTrans),
		SUM(td.CustomerWinLoss * e.Rate),
		SUM(td.LicenseeWinLoss * e.Rate),
		SUM(td.LicensingFee * e.Rate),
		SUM(td.ExtraPT * e.Rate),
		SUM(CASE WHEN td.ProductID = 21 THEN td.ServiceChargeOriginal * e21.Rate - td.RebateCommissionOriginal * e21.Rate - td.Promotion * e21.Rate
			ELSE td.PayToSupplier * e.Rate END),
		p.IsKeepNegativeAmount,
		SUM(WLShare * e.Rate),
		SUM(LicComm * e.Rate), 
		SUM(CommShare * e.Rate),
		SUM(CustomerWinLossSB * e.Rate),
		SUM(CustomerWinLossBA * e.Rate),
		SUM(CommissionA * e.Rate),
		SUM(CommissionS * e.Rate),
		SUM(CompanyTipShare* e.Rate),
		SUM(IncomeOnBB * e.Rate),
		SUM(IncomeOnProfitSharing * e.Rate),
		SUM(AmtDueToOnBB * e.Rate),
		SUM(AmtDueToOnProfitSharing * e.Rate),
		SUM(LicenseeChargeRate * e.Rate),
		SUM(JackpotPrize * e.Rate),
		SUM(LicenseeContribution * e.Rate),
		SUM(FullContribution * e.Rate),
		td.isDeposit,
		SUM(Promotion* e.Rate )
	
	FROM #TempData td 
	INNER JOIN #Exchange e ON e.ExchangeID = td.CurrencyId  AND e.ExchangeDate = td.Winlostdate
	LEFT JOIN  #Exchange e21 ON e21.ExchangeID = td.Playcurrency  AND e21.ExchangeDate = td.Winlostdate
	INNER JOIN #PartyList p ON td.PartyID = p.PartyId
	INNER JOIN #PartyList pa ON P.ParentId = pa.PartyId
	WHERE ProductID <> 32 -- PP handle outsite 
	GROUP BY pa.PartyId, pa.PartyName, td.PartyId, td.ProductID, p.IsKeepNegativeAmount, td.isDeposit


	BEGIN  -- Continue process #Result based on each special products
		IF EXISTS (SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SB') 
		BEGIN
			UPDATE #Result
			SET PayToSupplier = -(CustomerWinLossSB + CustomerWinLossBA + CommissionA + CommissionS) * @BetBuilderRate3rd
			WHERE ProductID = -1 -- BetBuilder
		
			UPDATE @productDataView
			SET ProductID = -1
			WHERE ProductCode = 'SB_BetBuilder'

			UPDATE #Result
			SET PayToSupplier = WLShare + CommShare
			WHERE ProductID = 0 -- MuayThai
		END 

		IF  EXISTS(SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'PPL') 
		BEGIN
			-- Detail
			;WITH CTE_Sum AS (
				SELECT t.PartyId, t.CurrencyId, t.WinLostDate, e.BaseCurrencyRate, SUM(t.LicenseeWinloss * e.BaseCurrencyRate) AS LicenseeWinloss, t.ProductID
				FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @CurrencyName) e
					INNER JOIN #TempData t ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = t.WinLostDate
				WHERE t.ProductID = 65
				GROUP BY t.PartyId, t.CurrencyId, t.WinLostDate, e.BaseCurrencyRate, t.ProductID
			), CTE_3rdRate AS (
				SELECT s.PartyId, s.CurrencyId, s.WinLostDate, SUM(CASE WHEN s.BaseCurrencyRate = 0 THEN 0 ELSE (CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.Rate / s.BaseCurrencyRate END) AS PayToSupplier, s.ProductID
				FROM CTE_Sum s
					INNER JOIN #3rdRatePPL r ON s.PartyId = r.PartyId AND s.ProductID = r.ProductID AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
				GROUP BY s.PartyId, s.CurrencyId, s.WinLostDate, s.ProductID
			)
			UPDATE t
			SET t.PayToSupplier = ISNULL(r.PayToSupplier, 0)
			FROM #TempData t
				LEFT JOIN CTE_3rdRate r ON t.PartyId = r.PartyId AND t.CurrencyId = r.CurrencyId AND t.WinLostDate = r.WinLostDate AND t.ProductID = r.ProductID
			WHERE t.ProductID = 65

			-- TotalByParty
			;WITH CTE_Sum AS (
				SELECT r.PartyId, r.ProductID, SUM(r.LicenseeWinloss * e.Rate) AS LicenseeWinloss
				FROM #TempData r
					INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLostDate = e.ExchangeDate
				WHERE  r.ProductID = 65
				GROUP BY r.PartyId, r.ProductID
			), CTE_3rdRate AS (
				SELECT r.PartyId, r.ProductID ,r.MinAmount * e.Rate AS MinAmount, r.MaxAmount * e.Rate AS MaxAmount, r.Rate
				FROM #3rdRatePPL r
					INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND e.ExchangeDate = @ToDate
			), CTE_Final AS (
				SELECT s.PartyId, s.ProductID ,SUM((CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.Rate) AS PayToSupplier
				FROM CTE_Sum s
					INNER JOIN CTE_3rdRate r ON s.PartyId = r.PartyId  AND s.ProductID = r.ProductID AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
				GROUP BY s.PartyId, s.ProductID
			)
			UPDATE t
			SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
			FROM #Result t
				LEFT JOIN CTE_Final f ON t.PartyId = f.PartyId AND t.ProductID = f.ProductID
			WHERE t.ProductID = 65
		END

	END


	IF  EXISTS(SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'PP')
	BEGIN
		;WITH TotalByParty AS(
			SELECT CASE WHEN p.PartyId = 14 THEN 14 ELSE p.ParentId END AS ParentId,
				CASE WHEN p.PartyId = 14 THEN '12Bet' ELSE pa.PartyName END AS ParentName,
				td.ProductID,
				SUM(td.TotalTrans)								TotalTrans,
				SUM(td.Promotion * e.BaseCurrencyRate)		WinPrizeAmount,
				SUM(ISNULL(td.JackpotPrize, 0) * e.BaseCurrencyRate)			JackpotPrize,
				SUM(ISNULL(td.LicenseeContribution, 0) * e.BaseCurrencyRate)	LicenseeContribution,
				SUM(ISNULL(td.FullContribution, 0) * e.BaseCurrencyRate)		FullContribution,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate)	CustomerWinLoss, 
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate)	LicenseeWinLoss, 
				SUM(td.LicensingFee * e.BaseCurrencyRate)		LicensingFee,
				SUM(ISNULL(td.LicenseeChargeRate, 0) * e.BaseCurrencyRate) LicenseeChargeRate,
				SUM(td.PayToSupplier * e.BaseCurrencyRate)		PayToSupplier
			FROM #TempData td 
			INNER JOIN #PartyList p ON p.PartyId = td.PartyID
			INNER JOIN #PartyList pa ON P.ParentId = pa.PartyId
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e  ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLostDate
			WHERE td.ProductID = 32
			GROUP BY CASE WHEN p.PartyId = 14 THEN 14 ELSE p.ParentId END,p.PartyId,CASE WHEN p.PartyId = 14 THEN '12Bet' ELSE pa.PartyName END,td.ProductID
		)
		INSERT INTO @PPTotal (ParentId,ParentName,ProductID,TotalTrans,WinPrizeAmount,JackpotPrize,LicenseeContribution,FullContribution,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT ParentId,
			ParentName,
			ProductID,
			SUM(TotalTrans),
			SUM(WinPrizeAmount),
			SUM(JackpotPrize),
			SUM(LicenseeContribution),
			SUM(FullContribution),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN ParentId = 999 THEN 0 -- Credit Licensee: always is 0
						ELSE CASE WHEN LicenseeChargeRate < 0 THEN 0 ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize - WinPrizeAmount
				END),
			SUM(PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId,ParentName,ProductID

		-- Region update PayToSupplier of Creadit
			;WITH SumByPropressiveAmount AS(
				SELECT  r.ParentId,
						SUM(CASE 
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName > MaxAmount THEN MaxAmount * e.BaseCurrencyRate 
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName  - MinAmount > 0 THEN (r.LicenseeWinloss - FullContribution) - (MinAmount * e.BaseCurrencyRate)
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN r.LicenseeWinloss - FullContribution
							ELSE 0 END  * roc.Rate)  AS ProgressiveAmount
				FROM @PPTotal r 
				INNER JOIN @RateOfCredit roc ON RowIndex <= @NumberOfTiers
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @BaseCurrencyName) e ON @CreditBaseCurrencyId = e.ExchangeID
				WHERE r.ParentId = 999 -- Credit Group Id
				GROUP BY r.ParentId 
			)
			UPDATE t
			SET PayToSupplier = ProgressiveAmount
			FROM @PPTotal t
			INNER JOIN SumByPropressiveAmount s  ON t.ParentId = s.ParentId
			
		-- Endregion update PayToSupplier of Creadit
		UPDATE @PPTotal
		SET PayToSupplier = CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END - WinPrizeAmount

		INSERT INTO @Total (ParentId, ParentName, ProductID,LicensingFee,PayToSupplier,CompanyIncome)
		SELECT ParentId, ParentName, ProductID,LicensingFee,PayToSupplier,LicensingFee - PayToSupplier FROM @PPTotal 
	END

	INSERT INTO @Total (ParentId, ParentName, ProductID,TotalTrans,CustomerWinLoss,LicenseeWinLoss,LicensingFee,ExtraPT,PayToSupplier,CompanyIncome,IncomeOnBB,IncomeOnProfitSharing,AmtDueToOnBB,AmtDueToOnProfitSharing,CustomerWinLossBA,CommissionA)
	SELECT 
		CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END,
		CASE WHEN  td.PartyId = 14 THEN '12Bet' ELSE td.ParentName END,
		td.ProductID,
		SUM(td.TotalTrans),
		SUM(td.CustomerWinLoss) ,
		SUM(td.LicenseeWinLoss) ,
		SUM(CASE
				
				 WHEN e.ProductID IS NOT NULL THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END + td.LicenseeContribution - td.JackpotPrize - td.Promotion END 
				   WHEN td.ProductID IN (21, 34, 55) THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END  END - td.Promotion
				  WHEN td.ProductID IN (73, 45, 79) THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END  - td.Promotion  END
				 WHEN td.LicensingFee < 0 AND p.isKeepNegativeFee = 0 AND td.IsKeepNegativeAmount = 0  THEN 0 
				 ELSE td.LicensingFee END + td.CompanyTipShare) AS LicensingFee,
		SUM(td.ExtraPT),
		SUM(CASE WHEN td.PayToSupplier < 0 AND p.isKeepNegativePayToSupplier = 0 THEN 0 ELSE td.PayToSupplier END) AS PayToSupplier,
		
		SUM(CASE WHEN td.ProductID = 23 THEN td.LicenseeWinLoss
				 WHEN e.ProductID IS NOT NULL THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END  + td.LicenseeContribution - td.JackpotPrize - td.Promotion END  
				  WHEN td.ProductID IN (21, 34, 55) THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END  END - td.Promotion
				  WHEN td.ProductID IN (73, 45, 79) THEN CASE WHEN td.IsDeposit = 0 THEN 0 ELSE CASE WHEN td.LicenseeChargeRate < 0 AND td.IsKeepNegativeAmount = 0 THEN 0 ELSE td.LicenseeChargeRate END  - td.Promotion  END
				  WHEN td.LicensingFee < 0 AND p.isKeepNegativeFee = 0 AND td.IsKeepNegativeAmount = 0 THEN 0 
				 ELSE td.LicensingFee END + td.CompanyTipShare)
		- SUM(CASE WHEN td.ProductID = 2 THEN td.ExtraPT ELSE 0 END) 
		- SUM(CASE WHEN td.PayToSupplier < 0 AND p.isKeepNegativePayToSupplier = 0 THEN 0 ELSE td.PayToSupplier END)  AS CompanyIncome,
		SUM(IncomeOnBB),
		SUM(IncomeOnProfitSharing),
		SUM(AmtDueToOnBB),
		SUM(AmtDueToOnProfitSharing) ,
		SUM(CustomerWinLossBA),
		SUM(CommissionA)			
	FROM #Result td 
	INNER JOIN @productDataView p ON td.ProductID = p.ProductID
	LEFT JOIN @ExtraAmtProduct e ON td.ProductID = e.ProductID AND e.ProductID <> 32
	GROUP BY 	CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END,
				CASE WHEN  td.PartyId = 14 THEN '12Bet' ELSE td.ParentName END, td.ProductID


	IF EXISTS(SELECT 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'PPL') 
	BEGIN
		-- Total
		;WITH CTE_Sum AS (
			SELECT CASE WHEN r.PartyId = 14 THEN 14 ELSE p.ParentId END ParentId, br.BaseCurrencyName, SUM(r.LicenseeWinloss * br.Rate) AS LicenseeWinloss
			FROM #TempData r
				INNER JOIN #PartyList p ON p.PartyId = r.PartyId
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND r.WinLostDate = br.ExchangeDate
			WHERE r.ProductID = 65
			GROUP BY CASE WHEN r.PartyId = 14 THEN 14 ELSE p.ParentId END, br.BaseCurrencyName
		), CTE_3rdRate AS (
			SELECT DISTINCT p.ParentId, br.BaseCurrencyName, r.MinAmount * br.Rate AS MinAmount, r.MaxAmount * br.Rate AS MaxAmount, r.Rate
			FROM #3rdRatePPL r
				INNER JOIN #PartyList p ON p.PartyId = r.PartyId
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND br.ExchangeDate = @ToDate
		), CTE_Final AS (
			SELECT s.ParentId, s.BaseCurrencyName, SUM(CASE WHEN 
														(CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.Rate < 0  THEN 0
														ELSE (CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss ELSE r.MaxAmount END - r.MinAmount) * r.Rate END
													  ) AS PayToSupplier
			FROM CTE_Sum s
				INNER JOIN CTE_3rdRate r ON s.ParentId = r.ParentId AND s.BaseCurrencyName = r.BaseCurrencyName AND (s.LicenseeWinloss > r.MinAmount OR (s.LicenseeWinloss < 0 AND r.MinAmount = 0))
			GROUP BY s.ParentId, s.BaseCurrencyName
		)
		UPDATE t
		SET t.PayToSupplier = ISNULL(f.PayToSupplier, 0)
		FROM @Total t
			LEFT JOIN CTE_Final f ON t.ParentId = f.ParentId AND f.BaseCurrencyName = @BaseCurrencyName
		WHERE t.ProductID = 65

		UPDATE t
		SET t.CompanyIncome = t.LicensingFee - t.PayToSupplier
		FROM @Total t
		WHERE t.ProductID = 65
	END

	-- Final result
	SELECT td.ParentId AS BillingGroupId,  
			td.ParentName AS BillingGroupName, 
			td.ProductID, 
			p.ProductName ,
			td.LicensingFee, 
			CASE WHEN td.ProductID = 25 THEN CASE WHEN  IncomeOnBB > IncomeOnProfitSharing THEN AmtDueToOnBB ELSE AmtDueToOnProfitSharing END
				 ELSE td.PayToSupplier END PayToSupplier, 
			CASE WHEN td.ProductID IN (10) THEN td.LicensingFee - td.PayToSupplier
				 WHEN td.ProductID = 25 THEN td.LicensingFee -  CASE WHEN  IncomeOnBB > IncomeOnProfitSharing THEN AmtDueToOnBB ELSE AmtDueToOnProfitSharing END
				 WHEN td.ProductID = -1 THEN td.LicensingFee - (td.CustomerWinLossBA + CommissionA) -  CASE WHEN td.PayToSupplier < 0 THEN 0 ELSE td.PayToSupplier END
			ELSE td.CompanyIncome END  CompanyIncome
	FROM @Total td
	INNER JOIN @productDataView p ON td.ProductID = p.ProductID
	ORDER BY ProductID, ParentId

	DROP TABLE  #3rdRatePPL
	DROP TABLE  #ChargeInfoWithCredit
	DROP TABLE  #3rdRate
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
	DROP TABLE  #AllbetPlayCurrency
END
GO