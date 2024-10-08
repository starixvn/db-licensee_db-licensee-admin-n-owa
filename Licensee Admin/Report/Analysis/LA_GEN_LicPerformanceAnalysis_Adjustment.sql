/*<info serverAlias="DBLIC-bodb_licenseeReport" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
USE bodb_licenseeReport
GO

ALTER PROCEDURE [dbo].LA_GEN_LicPerformanceAnalysis_Adjustment (
	@PartyIds		VARCHAR(MAX),
	@ReportDate		DATE,
	@Environment	VARCHAR(10),
	@IsOverwrite	BIT = 0
)
AS
/*
	Created: BRUCE
	Date: 20190312
	Task: Licensee Performance Analysis (PowerBI)
	DB: DBLIC.bodb_licenseeReport
	Remark: generate licensee performance analysis report: adjustment values

	Revisions:
		- 20190312@Bruce: create SP [RedmineID: #105205]
		- 20210323@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
	    - 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
		- 20201003@Danny: Exclude Licensees that offer cryptocurrency [#FeatureID 177718]
		- 20230815@Danny: Handle crypto licensee billing with fiat currency [RedmineID: #192378]
		- 20240401@Danny: Change meta data [#203267]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20241016@Danny: Extend parameter data length [RemineID: #212252]
		- 20241008@Sally: Support Odds Boost Voucher [#209884]

*/
BEGIN
	SET NOCOUNT ON

	DECLARE @AdjustmentId INT = 9000
	DECLARE @InvoiceStatus_void SMALLINT = -1
	
	SET @ReportDate = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportDate), 0)

	-- invoice item types
	--
	DECLARE @InvItemType_SoftwareFee SMALLINT = 1
	DECLARE @AdjustmentItemTypes TABLE(Id SMALLINT)
	INSERT INTO @AdjustmentItemTypes(Id)
	SELECT value FROM STRING_SPLIT('10,11,12,13,14,17,20',',')

	-- base currency list
	--
	DECLARE @tmpBaseCurrencyList TABLE(CurrencyId INT, Code VARCHAR(10))
	INSERT INTO @tmpBaseCurrencyList(CurrencyId,Code)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

	-- party list
	--
	DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)
	INSERT INTO @tmpPartyOfferCrypto(PartyId)
	SELECT  PartyID FROM bodb_licensee.dbo.LA_f_CryptoPartyListSel() WHERE IsBillingCryptoCurrency = 1

	DECLARE @tmpPartyList TABLE(PartyId INT, SiteId INT, BaseCurrencyId INT)
	INSERT INTO @tmpPartyList(PartyId,SiteId,BaseCurrencyId)
	SELECT p.PartyID, p.OldRefID, ISNULL(pbc_2.BaseCurrencyId, 6)-- Default EUR
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=p.PartyID
	INNER JOIN STRING_SPLIT(@PartyIds,',') v ON p.PartyID = v.value
	OUTER APPLY
	(
		SELECT TOP 1 pbc.PartyID, pbc.BaseCurrencyId
		FROM bodb_licensee.dbo.OAS_PartyBaseCurrency pbc WITH(NOLOCK)
		WHERE pbc.PartyID = p.PartyId AND @ReportDate BETWEEN FromDate AND ToDate
		ORDER BY ToDate DESC
	) pbc_2
	WHERE p.PartyType = 1 AND p.PartyID NOT IN (SELECT x.PartyId FROM @tmpPartyOfferCrypto x)
	-- if not overwrite old values then skip
	--
	DECLARE @Skip TABLE(SiteId INT)
	IF @IsOverwrite = 0 INSERT INTO @Skip(SiteId)
	(
		SELECT DISTINCT a.SiteId
		FROM dbo.rptLicPerformanceAnalysis a WITH(NOLOCK)
		WHERE a.ReportDate = @ReportDate AND ProductId = @AdjustmentId
	)

	-- adjustment values
	--
	DECLARE @tmpAmounts TABLE(USD MONEY, EUR MONEY, MYR MONEY,GBP MONEY,CNY MONEY, SiteId INT, BaseCurrencyId INT)

	;WITH cte_Adjustment AS
	(
		SELECT CAST(InvoiceDate AS DATE)AS StatementDate, (ISNULL(s.Income,0) -ISNULL(s.Expense,0)) AS Amount, h.CurrencyId, p.SiteId, p.BaseCurrencyId
		FROM bodb_licensee.dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @AdjustmentItemTypes r ON r.Id = s.InvItemTypeId
		INNER JOIN @tmpPartyList p ON p.PartyID=h.PartyId
		WHERE h.Environment = @Environment
			AND h.StatusId <> @InvoiceStatus_void
			AND @ReportDate  = DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0)
			AND p.SiteId NOT IN (SELECT s.SiteId FROM @Skip s)
	)
	INSERT INTO @tmpAmounts(SiteId,BaseCurrencyId, USD,EUR,MYR,GBP,CNY)
	SELECT a.SiteId,a.BaseCurrencyId,
		a.Amount * e.USD,
		a.Amount * e.EUR,
		a.Amount * e.MYR,
		a.Amount * e.GBP,
		a.Amount * e.CNY
	FROM cte_Adjustment a
	INNER JOIN bodb02.dbo.ExchangeDailyOanda e WITH(NOLOCK) ON e.ExchangeDate = a.StatementDate AND e.ExchangeId = a.CurrencyId

	-- Remove old values
	--
	DELETE dbo.rptLicPerformanceAnalysis
	WHERE ReportDate = @ReportDate AND ProductId = @AdjustmentId 
		AND SiteId IN (SELECT a.SiteId FROM @tmpPartyList a)
		AND SiteId NOT IN (SELECT b.SiteId FROM @Skip b)

	-- Generate adjustment
	--
	DECLARE @Code VARCHAR(5)
	DECLARE @CurrencyId INT
	WHILE EXISTS(SELECT * FROM @tmpBaseCurrencyList)
	BEGIN
		SELECT TOP 1 @Code=Code, @CurrencyId = CurrencyId FROM @tmpBaseCurrencyList
		DELETE @tmpBaseCurrencyList WHERE @Code = Code

		INSERT INTO dbo.rptLicPerformanceAnalysis(ReportDate,SiteId,ProductId,CurrencyId,BetCount,Turnover,TurnoverNoDraw,LicenseeWinloss,LicensingFee,Discount,Rebate,IsBillingCurrency,Adjustment,OddsBoostBonus)
		SELECT @ReportDate,SiteId,@AdjustmentId,@CurrencyId,0,0,0,0,0,0,0,
			CASE WHEN @CurrencyId = BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency,
			SUM(CASE
				WHEN @Code = 'USD' THEN USD
				WHEN @Code = 'CNY' THEN CNY
				WHEN @Code = 'MYR' THEN MYR
				WHEN @Code = 'GBP' THEN GBP
				ELSE EUR
			END),
			0 AS OddsBoostBonus
		FROM @tmpAmounts
		GROUP BY SiteId, CASE WHEN @CurrencyId = BaseCurrencyId THEN 1 ELSE 0 END
	END
END
GO