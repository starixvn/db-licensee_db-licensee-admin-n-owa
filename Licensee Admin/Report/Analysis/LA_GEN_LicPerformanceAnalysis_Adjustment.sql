/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].LA_GEN_LicPerformanceAnalysis_Adjustment (
	@PartyIds		VARCHAR(4000),
	@ReportDate		DATE,
	@Environment	VARCHAR(10),
	@IsOverwrite	BIT = 0
)
AS
/*
	Created: BRUCE
	Date: 20190312
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee
	Remark: generate licensee performance analysis report: adjustment values

	Revisions:
		- 20190312@Bruce: create SP [RedmineID: #105205]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @AdjustmentId INT = 9000
	DECLARE @InvoiceStatus_Normal SMALLINT = 0
	
	SET @ReportDate = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportDate), 0)

	-- invoice item types
	--
	DECLARE @InvItemType_SoftwareFee SMALLINT = 1
	DECLARE @AdjustmentItemTypes TABLE(Id SMALLINT)
	INSERT INTO @AdjustmentItemTypes(Id)
	SELECT val FROM dbo.strSplit('10,11,12,13,14,17,20',',')

	-- base currency list
	--
	DECLARE @tmpBaseCurrencyList TABLE(CurrencyId INT, Code VARCHAR(10))
	INSERT INTO @tmpBaseCurrencyList(CurrencyId,Code)
	EXEC dbo.LA_SelBaseCurrency

	-- party list
	--
	DECLARE @tmpPartyList TABLE(PartyId INT, SiteId INT, BaseCurrencyId INT)
	INSERT INTO @tmpPartyList(PartyId,SiteId,BaseCurrencyId)
	SELECT p.PartyID, p.OldRefID,d.BaseCurrencyId
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=p.PartyID
	WHERE p.PartyType = 1 AND p.PartyID IN (SELECT val FROM dbo.strSplit(@PartyIds,','))

	-- if not overwrite old values then skip
	--
	DECLARE @Skip TABLE(SiteId INT)
	IF @IsOverwrite = 0 INSERT INTO @Skip(SiteId)
	(
		SELECT DISTINCT a.SiteId
		FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis a WITH(NOLOCK)
		WHERE a.ReportDate = @ReportDate AND ProductId = @AdjustmentId
	)

	-- adjustment values
	--
	DECLARE @tmpAmounts TABLE(USD MONEY, EUR MONEY, MYR MONEY,GBP MONEY,CNY MONEY, SiteId INT, BaseCurrencyId INT)

	;WITH cte_Adjustment AS
	(
		SELECT CAST(InvoiceDate AS DATE)AS StatementDate, (ISNULL(s.Income,0) -ISNULL(s.Expense,0)) AS Amount, h.CurrencyId, p.SiteId, p.BaseCurrencyId
		FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
		INNER JOIN @AdjustmentItemTypes r ON r.Id = s.InvItemTypeId
		INNER JOIN @tmpPartyList p ON p.PartyID=h.PartyId
		WHERE h.Environment = @Environment
			AND h.StatusId = @InvoiceStatus_Normal
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
	DELETE bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis
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

		INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis(ReportDate,SiteId,ProductId,CurrencyId,BetCount,Turnover,TurnoverNoDraw,LicenseeWinloss,LicensingFee,Discount,Rebate,IsBillingCurrency,Adjustment)
		SELECT @ReportDate,SiteId,@AdjustmentId,@CurrencyId,0,0,0,0,0,0,0,
			CASE WHEN @CurrencyId = BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency,
			SUM(CASE
				WHEN @Code = 'USD' THEN USD
				WHEN @Code = 'CNY' THEN CNY
				WHEN @Code = 'MYR' THEN MYR
				WHEN @Code = 'GBP' THEN GBP
				ELSE EUR
			END)
		FROM @tmpAmounts
		GROUP BY SiteId, CASE WHEN @CurrencyId = BaseCurrencyId THEN 1 ELSE 0 END
	END
END
GO