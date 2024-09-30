/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeInfoSel]
	 @PartyIds VARCHAR(MAX) = ''
AS
/*
	Created: 20151007@Bruce
	Task : Get Licensee information
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20151007@Bruce: Get Licensee information
		- 20180125@Bruce: include branch name [#90029]
		- 20180301@Parsons: inlclude CO to Licensee List [#90721]
		- 20180801@Parsons: Rebuild licensee information report [#94283]
		- 20190130@Bruce: Missing licensee group: Cozni [#108432]
		- 20190318@Mason: Add InvoiceLanguage in SELECT statement [#110445]
		- 20200212@Mason: Set billing term by currency [#120005]
		- 20210811@Percy: Add input parameter: @PartyIds (list of PartyId) [RedmineID: #159629]
		- 20220118@Percy: Add Licensee Status Setting [RedmineID: #166751]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20230828@Danny: Enhance Licensee Information report [RemineID: #191248]
		- 20240717@Danny: Return Master Currency Codes [RedmineID: #206117]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @currentDate DATE = GETDATE()

	DECLARE @Groups AS TABLE (PartyID INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	DECLARE @EmptyDate AS DATE = NULL

	CREATE TABLE #PartyIdTab (ID INT identity (1,1), PartyID INT)
	INSERT INTO #PartyIdTab (PartyID)
	SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds, ',')

	CREATE TABLE  #tmp_CurrencyInfo (PartyID INT, CurrencyId INT, CurrencyCode VARCHAR(65), CurrencyName VARCHAR(20))

	INSERT INTO #tmp_CurrencyInfo (PartyID, CurrencyId, CurrencyCode, CurrencyName)

	SELECT  pt.PartyID, lc.Currency, lc.Code, lc.CurrencyName
	FROM	#PartyIdTab pt
	INNER JOIN OAS_Party op WITH(NOLOCK) ON pt.PartyID = op.PartyID
	CROSS APPLY (
		SELECT DISTINCT lc.Currency,
						CASE WHEN lc.Currency = 92 THEN 'HID'
								WHEN lc.Currency = 142 THEN 'USDT'
								WHEN lc.Currency IN (96, 202, 206, 208, 209) THEN e.Code + ' (' + e.Currency + ')' 
							ELSE e.Code END AS Code, 
						CASE WHEN lc.Currency = 51 THEN 'VND' ELSE e.currency END AS CurrencyName
		FROM dbo.LA_f_SelLicenseeCust(op.OldRefID) AS lc
		INNER JOIN CustDB.dbo.Exchange e WITH (NOLOCK) ON lc.currency = e.exchangeid
		WHERE lc.Currency NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x) -- exclude test
	) lc

	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM #tmp_CurrencyInfo c1
	INNER JOIN (
		SELECT CurrencyCode, PartyID
	    FROM #tmp_CurrencyInfo
	    GROUP BY CurrencyCode, PartyID
	    HAVING COUNT(1) > 1
	) c2 ON c1.CurrencyCode = c2.CurrencyCode AND c1.PartyID = c2.PartyID

	-- Group: 'ONEWorks','Boping', 'Zelianta', 'Price Feed'
	INSERT INTO @Groups(PartyID,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel
	-- FILTERED CHARGE INFO
	--
	-- PartyType  = 1 : Licensee
	-- ChargeType = 1 : Charge by Gross Win
	-- SystemId   = 2 : LA
	--
	;WITH ChargeInfo AS(
		SELECT ci.ProductId, ci.FromParty, ci.ToParty, ci.Rate, ci.FromDate, ci.ToDate, ci.ChargeID, ci.ChargeType AS RateType
		FROM dbo.OAS_ChargeInfo AS ci WITH (NOLOCK)
		INNER JOIN #PartyIdTab p2 ON ci.FromParty = p2.PartyID
		WHERE ProductId NOT IN (14, 17)
		UNION ALL
		SELECT s.ProductId, s.FromParty, s.ToParty, s.Rate, s.FromDate, s.ToDate, s.ChargeIdRef, s.BettypeRef AS RateType
		FROM dbo.OAS_ChargeInfoSub AS s WITH (NOLOCK) 
		INNER JOIN #PartyIdTab p2 ON s.FromParty = p2.PartyID
		WHERE s.ChargeType = 1
	)
	SELECT	 CASE pd.IsDeposit	WHEN 0 THEN 'Credit' ELSE g.PartyName							END AS GroupName
			,CASE p.PartyName	WHEN 'IBC' THEN 'FDL' WHEN '18bb'THEN 'PIH' ELSE p.PartyName	END AS LicenseeName
			,ci.ToDate
			,w.WaiveMonth AS WaiveMonth
			,CAST(ISNULL(ci.Rate, 0) AS MONEY) AS Rate
			,ci.FromDate
			,f.FeeAmount
			,ci.ProductId
			,pd.IsDeposit
			,ci.RateType
			,pd.BrandName
			,pd.InvoiceLanguage
			,ci.ChargeId
			,pd.LaunchDate
			,pd.SuspendedDate
			,pd.TerminatedDate
			,mc.MasterCurrencyCodes
	FROM ChargeInfo AS ci
		INNER JOIN dbo.OAS_Party AS p WITH (NOLOCK) ON p.PartyID = ci.FromParty			-- Licensee
		INNER JOIN @Groups AS g ON ci.ToParty = g.PartyID								-- Group
		INNER JOIN dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID	-- Credit
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping s WITH (NOLOCK) ON s.ChargeID=ci.ChargeID AND s.SystemID = 2
		OUTER APPLY 
		(
			SELECT TOP 1 f.FeeAmount
			FROM dbo.LA_Minfee f WITH (NOLOCK) 
			WHERE f.PartyId = ci.FromParty AND f.ProductId=ci.ProductId AND f.FeeTypeId = 1 -- Min fee
			ORDER BY f.FromDate DESC
		) f 
		OUTER APPLY (
			SELECT SUM(DATEDIFF(MONTH, w.FromDate, DATEADD(DAY, 1, w.ToDate)) + CASE WHEN DAY(w.FromDate) > DAY(DATEADD(DAY, 1, w.ToDate)) THEN -1 ELSE 0 END) AS WaiveMonth
			FROM dbo.LA_MinFee w WITH (NOLOCK)
			WHERE w.PartyId = p.PartyId AND w.FeeTypeId = 2
		) w

		OUTER APPLY (
			SELECT STRING_AGG(tc.CurrencyCode,',') MasterCurrencyCodes 
			FROM #tmp_CurrencyInfo tc
			LEFT JOIN LA_ChargeRateByCurrency lc WITH(NOLOCK) ON lc.ChargeID = ci.ChargeId AND tc.CurrencyId = lc.CurrencyID 
			WHERE lc.CurrencyID IS NULL AND tc.PartyID = ci.FromParty
		) mc
			
	WHERE g.ParentId = 0 AND p.PartyType = 1
	ORDER BY p.PartyName, pd.BrandName, ci.FromDate, ci.ProductID

	DROP TABLE #tmp_CurrencyInfo
	DROP TABLE #PartyIdTab
END
GO