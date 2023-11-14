/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @currentDate DATE = GETDATE()

	DECLARE @Groups AS TABLE (PartyID INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	DECLARE @EmptyDate AS DATE = NULL

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
		WHERE ProductId NOT IN (14, 17)
		UNION ALL
		SELECT s.ProductId, s.FromParty, s.ToParty, s.Rate, s.FromDate, s.ToDate, s.ChargeIdRef, s.BettypeRef AS RateType
		FROM dbo.OAS_ChargeInfoSub AS s WITH (NOLOCK) 
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
			
		INNER JOIN STRING_SPLIT(@PartyIds, ',') p2 ON p.PartyID = p2.value
	WHERE g.ParentId = 0 AND p.PartyType = 1
	ORDER BY p.PartyName, pd.BrandName, ci.FromDate, ci.ProductID
END
GO