/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeInfoSel]
AS
/*
	Created: 20151007@Bruce
	Task : Get Licensee information
	DB: DB052.bodb_Licensee

	Revisions:
	- 20151007@Bruce: Get Licensee information
	- 20180125@Bruce: include branch name [#90029]
	- 20180301@Parsons: inlclude CO to Licensee List [#90721]
	- 20180801@Parsons: Rebuild licensee information report [#94283]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Groups AS TABLE (PartyID INT, PartyName VARCHAR(50))
	DECLARE @EmptyDate AS DATE = NULL

	-- Group: 'ONEWorks','Boping', 'Zelianta', 'Price Feed'
	INSERT INTO @Groups (PartyID, PartyName)
	SELECT PartyID, PartyName
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE PartyName IN ('ONEWorks','Boping', 'Zelianta', 'Price Feed')

	-- FILTERED CHARGE INFO
	--
	-- PartyType  = 1 : Licensee
	-- ChargeType = 1 : Charge by Gross Win
	-- SystemId   = 2 : LA
	--
	;WITH ChargeInfo AS(
		SELECT ci.ProductId, ci.FromParty, ci.ToParty, ci.Rate, ci.FromDate, ci.ToDate, ci.ChargeID, ci.ChargeType AS [Type]
		FROM dbo.OAS_ChargeInfo AS ci WITH (NOLOCK)
		WHERE ProductId NOT IN (14, 17)
		UNION ALL
		SELECT s.ProductId, s.FromParty, s.ToParty, s.Rate, s.FromDate, s.ToDate, s.ChargeIdRef, s.BettypeRef AS [Type]
		FROM dbo.OAS_ChargeInfoSub AS s WITH (NOLOCK)
		WHERE s.ChargeType = 1
	)
	SELECT	 CASE pd.IsDeposit	WHEN 0 THEN 'Credit' ELSE g.PartyName							END AS GroupName
			,CASE p.PartyName	WHEN 'IBC' THEN 'FDL' WHEN '18bb'THEN 'PIH' ELSE p.PartyName	END AS LicenseeName
			,CASE ci.ToDate		WHEN '2050-01-01' THEN @EmptyDate ELSE ci.ToDate				END AS ToDate
			,DATEDIFF(m, m.FromDate, m.ToDate) AS WaiveMonth
			,CAST(ISNULL(ci.Rate, 0) AS MONEY) AS Rate
			,ci.FromDate
			,f.FeeAmount
			,ci.ProductId
			,pd.IsDeposit
			,ci.[Type]
			,pd.BrandName
	FROM ChargeInfo AS ci
		INNER JOIN dbo.OAS_Party AS p WITH (NOLOCK) ON p.PartyID = ci.FromParty			-- Licensee
		INNER JOIN @Groups AS g ON ci.ToParty = g.PartyID								-- Group
		INNER JOIN dbo.OAS_PartyDetail AS pd WITH (NOLOCK) ON pd.PartyID = p.PartyID	-- Credit
		LEFT JOIN dbo.LA_Minfee AS f WITH (NOLOCK) ON f.PartyId = ci.FromParty AND f.ProductId=ci.ProductId AND f.FeeTypeId = 1 -- Min fee
		LEFT JOIN dbo.LA_Minfee AS m WITH (NOLOCK) ON m.PartyId = ci.FromParty AND m.ProductId=ci.ProductId AND m.FeeTypeId = 2 -- Waive month
	WHERE p.PartyType = 1 AND ci.ChargeID IN (	SELECT ChargeID 
												FROM dbo.LA_ChargeInfo_SystemMapping WITH (NOLOCK)
												WHERE SystemID = 2)
	ORDER BY p.PartyName, pd.BrandName, ci.FromDate, ci.ProductID
END
GO