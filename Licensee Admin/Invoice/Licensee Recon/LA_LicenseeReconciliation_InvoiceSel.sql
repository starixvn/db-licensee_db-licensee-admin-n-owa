/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_InvoiceSel]
	@PartyIds		VARCHAR(4000),
	@FromDate		DATE,
	@ToDate			DATE,
	@Environment	VARCHAR(50) = 'DEV',
	@IsGroupByPartyId	BIT = 0
AS

/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190905@Bruce: Create Sp [#111586]
		- 20190924@Bruce: Include actual invoice, prepayment, cn/dn data and setupfee amount [#120220]
		- 20191016@Bruce: [#122229]
			+ Group data by code or by party id
			+ Check FromDate for sofrware data fee & Rebate ( type = 1 )
		- 20191219@Bruce: Exclude credit notes in calculation of Recon and Collection sheet [#125779]
		- 20191210@Bruce: Include Promotion [#123958]
		- 20200729@Parsons: Implement PP Jackpot [RedmineID: #137306]
		- 20201104@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
	    - 20201218@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
	   	- 20210323@Percy: Support duo base currency [RedmineID: #152089]
		- 20210407@Percy: Support duo base currency - Change code for Collection Summary [RedmineID: #152089]
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20220110@Danny: SG - Jackpot prize integration [#167089]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20220222@Danny: Allbet - Promotion integration [#167510]
		- 20220418@Percy: Add Credit for Setup Fees [RedmineID: #164139]
		- 20221028@Danny: MG-RNG offer tournament prize [RedmineID: #176986]
*/
BEGIN
	SET NOCOUNT ON

	-- get base currency
	--
	DECLARE @baseCurrencyList TABLE (CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT INTO @baseCurrencyList(CurrencyId,CurrencyName)
	SELECT CurrencyId,CurrencyName FROM OPENQUERY(DBCUST, 'EXEC CustDB.dbo.LA_BaseCurrency_Sel') 

	-- get party list
	--
	DECLARE @partyList AS TABLE(PartyId INT,LicenseeCode VARCHAR(50), BaseCurrencyId INT)

	INSERT INTO @partyList(PartyId, LicenseeCode, BaseCurrencyId)
	SELECT PartyID, UPPER(LicenseeCode), BaseCurrencyId
	FROM dbo.OAS_PartyBaseCurrency WITH(NOLOCK)
	WHERE (@IsGroupByPartyId = 1 OR LicenseeCode IS NOT NULL)
		AND @ToDate BETWEEN FromDate AND ToDate

	IF @PartyIds <> 'All'
	BEGIN
		DELETE @partyList WHERE PartyID NOT IN (SELECT val FROM dbo.strSplit(@PartyIds, ','))
	END

	DECLARE @N_FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate) + 1, 0)
	DECLARE @N_ToDate DATE = DATEADD (DAY, -1, DATEADD(MONTH, 1, @N_FromDate))

	SELECT p.LicenseeCode, b.CurrencyName, r.ProductName, p.PartyId
		,SUM(CASE WHEN InvItemTypeId IN (1,30,31,32,33,34,35,36,37,38,39,40,41,42,43,47) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) LicensingFee
		,SUM(CASE WHEN InvItemTypeId = 4 THEN ISNULL(Expense,0) ELSE 0 END) Discount
		,SUM(CASE WHEN InvItemTypeId = 6 THEN ISNULL(Expense,0) ELSE 0 END) Rebate
		,SUM(CASE WHEN InvItemTypeId IN (5,24,26) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Prepayment
		,SUM(CASE WHEN InvItemTypeId IN (11,12,13,14,17,20) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Others
		,SUM(CASE WHEN InvItemTypeId = 45 THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) Others2
		,SUM(CASE WHEN InvItemTypeId IN (3,25) THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) AMF
		,SUM(CASE WHEN InvItemTypeId = 46 THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) AMF2
		,SUM(CASE WHEN InvItemTypeId = 2 THEN ISNULL(Income,0) - ISNULL(Expense,0) ELSE 0 END) SetupFee
		,SUM(CASE WHEN InvItemTypeId = 29 THEN ISNULL(Expense,0) ELSE 0 END) Promotion
		,SUM(CASE WHEN InvItemTypeId = 44 THEN ISNULL(Expense,0) ELSE 0 END) Sponsorship
	INTO #result
	FROM @partyList p
	INNER JOIN dbo.LA_InvoiceHeader h WITH(NOLOCK) ON p.PartyId = h.PartyId AND h.CurrencyId = p.BaseCurrencyId
	INNER JOIN @baseCurrencyList b ON h.CurrencyId = b.CurrencyId
	INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
	LEFT JOIN dbo.LA_f_Products3rd('') r ON r.ProductID = s.ProductId
	WHERE h.StatusId = 0-- normal invoice
		AND h.InvoiceHeaderId NOT IN (6208, 6207) -- temporary exclude these credit notes
		AND h.Environment = @Environment
		AND 1 = CASE
					WHEN h.InvoiceType IN (1, 3) AND h.FromDate BETWEEN @FromDate AND @ToDate THEN 1
					WHEN h.InvoiceType = 7 AND h.InvoiceDate BETWEEN @FromDate AND @ToDate THEN 1
					WHEN h.InvoiceType = 4 AND s.InvItemTypeId IN (45, 46) AND h.InvoiceDate BETWEEN @FromDate AND @ToDate THEN 1
					WHEN h.InvoiceType IN (4, 5) AND s.InvItemTypeId NOT IN (45, 46) AND h.InvoiceDate BETWEEN @N_FromDate AND @N_ToDate THEN 1
					ELSE 0 END
	GROUP BY p.LicenseeCode, b.CurrencyName, r.ProductName, p.PartyId

	-- Deduct prepayment if Setup Fee & Credit Note for Setup Fee same month
	UPDATE #result
	SET AMF = AMF + AMF2
	WHERE
		(SetupFee <> 0 OR AMF <> 0)
		AND (AMF2 <> 0)

	IF @IsGroupByPartyId = 0
	BEGIN
		SELECT ISNULL(LicenseeCode, '') + '|' + CONVERT(VARCHAR(50), PartyId) AS LicenseeCode
			,CurrencyName
			,0 AS PartyId
			,SUM(LicensingFee) LicensingFee
			,SUM(Discount) Discount
			,SUM(Rebate) Rebate
			,SUM(Prepayment) Prepayment
			,SUM(Others) Others
			,SUM(Others2) Others2
			,SUM(SetupFee) SetupFee
			,SUM(AMF) AMF
			,SUM(Promotion) Promotion
			,SUM(Sponsorship) Sponsorship
		FROM #result
		GROUP BY ISNULL(LicenseeCode, '') + '|' + CONVERT(VARCHAR(50), PartyId), CurrencyName
		ORDER BY LicenseeCode
	END
	ELSE
	BEGIN
		SELECT PartyId,CurrencyName
			,'' AS LicenseeCode
			,SUM(LicensingFee) LicensingFee
			,SUM(Discount) Discount
			,SUM(Rebate) Rebate
			,SUM(Prepayment) Prepayment
			,SUM(Others) Others
			,SUM(Others2) Others2
			,SUM(SetupFee) SetupFee
			,SUM(AMF) AMF
			,SUM(Promotion) Promotion
			,SUM(Sponsorship) Sponsorship
		FROM #result
		GROUP BY PartyId, CurrencyName
	END

	DROP TABLE #result
END
GO