/*<info serverAlias="DBLIC-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER FUNCTION [dbo].[LA_f_ChargeInfoWithCredit] (
	@PartyIDs			VARCHAR(MAX)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @ProductCodes		VARCHAR(1000)
	)
RETURNS @tbChargeInfo TABLE (
	 ChargeID			INT
	, PartyID			INT
	, LicenseeID		INT
	, isDeposit			INT
	, AffectedDate		SMALLDATETIME
	, ProductID			INT
	, Bettype			INT DEFAULT -1
	, DI_Rate			MONEY
	, OW_Rate			MONEY
	, PNR_Rate			MONEY
	, Fromdate			SMALLDATETIME
	, Todate			SMALLDATETIME
	, ChargeType		TINYINT
	)
AS
/*  Created: 20180815@Scofield
    Task : Get Charge Information for Credit
    DB: DBLIC.bodb_Licensee
    
	Revisions:
		- 20180815@Scofield: Get charge rate for Credits	
		- 20190718@Bruce: Integrate CN88 data in LA [#116859]
		- 20241016@Danny: Extend parameter data length [RemineID: #212252]
*/

BEGIN
	DECLARE @SystemID INT
	SELECT @SystemID = id FROM dbo.Systems WITH (NOLOCK) WHERE SystemName = 'OA'
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

	DECLARE @ProductTable TABLE (ProductID smallint, ProductPrefix varchar(20))
	DECLARE @Bettype TABLE (ProductId smallint, BetTypeRef smallint, BetType smallint)

	INSERT INTO @ProductTable (ProductID, ProductPrefix)
	SELECT CASE
			WHEN s.val = 'SB'
				THEN 0
			ELSE p3.Productid
			END
			, s.val
	FROM bodb02.dbo.strSplit(@ProductCodes, ',') s
		LEFT JOIN dbo.Product3rd p3 WITH (NOLOCK) ON s.val = p3.ProductPrefix
	
	INSERT INTO @Bettype(ProductId, BetTypeRef, Bettype)
	SELECT pt.ProductID, sbr.BettypeRef, sbm.BetType
	FROM @ProductTable pt
	 INNER JOIN bodb02.dbo.Products p ON pt.ProductPrefix = p.ProductPrefix
	 INNER JOIN bodb02.dbo.SportBettypeMatrix sbm ON p.ProductID = sbm.ProductID
	 INNER JOIN dbo.Sport_Bettype_Reference sbr ON sbm.BetType = sbr.Bettype
		
	DECLARE @Cte_AffectDate TABLE (AffectedDate DATE, PartyID INT, ProductID INT) 

	INSERT INTO @Cte_AffectDate (AffectedDate, PartyID, ProductID)
	(
	    SELECT MIN(FromDate) AS AffectedDate
		  , FromParty AS PartyID
		  , ci.ProductID
	    FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
	    WHERE ChargeType != 2
		  AND p.PartyID IN (SELECT VAL FROM strSplit(@PartyIDs, ','))
		  AND ci.ProductID NOT IN (SELECT Productid FROM dbo.LA_Product3rdSub WITH (NOLOCK))		  
	    GROUP BY FromParty, ci.ProductID
	)
	
    INSERT INTO @tbChargeInfo (ChargeID , PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate, ChargeType)
	SELECT DISTINCT DI.ChargeID 
		, p.PartyID
		, CASE 
		 	WHEN ISNULL(pd.IsDeposit, 0) = 1
		 		THEN p.OldRefID
		 	ELSE lb.LabelID
		 	END AS LicenseeID
		, pd.IsDeposit
		, cte.AffectedDate
		, DI.ProductID
		, CASE WHEN DI.Rate = 0 THEN ISNULL(OW.Rate,0) ELSE DI.Rate END AS DI_Rate	
		, ISNULL(ow.Rate, 0)	 AS OW_Rate  -- not use now
		, 0	 AS PNR_Rate -- not use now
		, CASE 
		 	WHEN @FromDate <= DI.FromDate 
		 		THEN DI.FromDate
		 	ELSE @FromDate
		 	END
		, CASE 
			WHEN @ToDate >= DI.ToDate 
				THEN DI.ToDate
			ELSE @ToDate
			END
		, DI.ChargeType
	FROM dbo.OAS_Party p WITH (NOLOCK)	
		INNER JOIN dbo.OAS_ChargeInfo DI WITH (NOLOCK) ON DI.FromParty = p.PartyID	AND DI.ChargeType != 2 AND p.PartyType = 1
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON DI.ChargeID = cs.ChargeID AND cs.SystemID = @SystemID
		LEFT JOIN dbo.OAS_ChargeInfo OW WITH (NOLOCK) ON DI.ParentChargeID = OW.ChargeID	
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
		LEFT JOIN @Cte_AffectDate cte ON cte.PartyID = p.PartyID
			AND DI.ProductID = cte.ProductID
	WHERE p.PartyID IN (
			SELECT VAL
			FROM strSplit(@PartyIDs, ',')
			)		
		AND (
			@FromDate BETWEEN DI.FromDate AND DI.ToDate
			OR @ToDate BETWEEN DI.FromDate AND DI.ToDate
			OR DI.FromDate BETWEEN @FromDate AND @ToDate
			OR DI.ToDate BETWEEN @FromDate AND @ToDate
			)
		AND DI.ProductID IN (
			SELECT ProductID FROM @ProductTable
			)
		AND NOT EXISTS (SELECT 1 FROM dbo.OAS_ChargeInfoSub WITH (NOLOCK) WHERE DI.ChargeID = ChargeIDRef)
		AND DI.ChargeType != 11 -- rolling commission
		AND NOT EXISTS (SELECT 1 FROM dbo.OAS_Party t WITH (NOLOCK) WHERE DI.FromParty NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl) AND DI.ToParty = t.PartyID AND t.PartyType = 3 AND (t.OldRefID IS NULL OR t.OldRefID IN (2, 3, 5, 6)))
	ORDER BY p.PartyID
		,Di.ProductID
		
	--case multi chargerate
	INSERT INTO @Cte_AffectDate (AffectedDate, PartyID, ProductID)
	(
	    SELECT MIN(s.FromDate) AS AffectedDate
		  , ci.FromParty AS PartyID
		  , ci.ProductID
	    FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
			INNER JOIN dbo.OAS_ChargeInfoSub s WITH (NOLOCK) ON s.ChargeIDRef = ci.ChargeID AND s.FromParty = ci.FromParty
	    WHERE ci.ChargeType != 2
		  AND p.PartyID IN (SELECT VAL FROM strSplit(@PartyIDs, ','))		
		  AND ci.ProductID IN (SELECT Productid FROM dbo.LA_Product3rdSub WITH (NOLOCK))	  
	    GROUP BY ci.FromParty, ci.ProductID
	)

	INSERT INTO @tbChargeInfo (ChargeID , PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Bettype, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate, ChargeType)
	SELECT DISTINCT DI.ChargeID 
		, p.PartyID
		, CASE 
		 	WHEN ISNULL(pd.IsDeposit, 0) = 1
		 		THEN p.OldRefID
		 	ELSE lb.LabelID
		 	END AS LicenseeID
		, pd.IsDeposit
		, cte.AffectedDate
		, DI.ProductID
		, sbr.BetTypeRef
		, sub.Rate DI_Rate	
		, 0	 AS OW_Rate  -- not use now
		, 0	 AS PNR_Rate -- not use now
		, CASE 
		 	WHEN @FromDate <= sub.FromDate 
		 		THEN sub.FromDate
		 	ELSE @FromDate
		 	END
		, CASE 
			WHEN @ToDate >= sub.ToDate 
				THEN sub.ToDate
			ELSE @ToDate
			END
		, DI.ChargeType
	FROM dbo.OAS_Party p WITH (NOLOCK)	
		INNER JOIN dbo.OAS_ChargeInfo DI WITH (NOLOCK) ON DI.FromParty = p.PartyID AND DI.ChargeType != 2 AND p.PartyType = 1
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON DI.ChargeID = cs.ChargeID AND cs.SystemID = @SystemID
		INNER JOIN dbo.OAS_ChargeInfoSub sub WITH (NOLOCK) ON DI.ChargeID = sub.ChargeIDref
		INNER JOIN @Bettype sbr ON sbr.BetTypeRef = sub.BettypeRef
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
		LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
		LEFT JOIN @Cte_AffectDate cte ON cte.PartyID = p.PartyID
			AND DI.ProductID = cte.ProductID
	WHERE p.PartyID IN (
			SELECT VAL
			FROM strSplit(@PartyIDs, ',')
			)		
		AND (
			@FromDate BETWEEN sub.FromDate AND sub.ToDate
			OR @ToDate BETWEEN sub.FromDate AND sub.ToDate
			OR sub.FromDate BETWEEN @FromDate AND @ToDate
			OR sub.ToDate BETWEEN @FromDate AND @ToDate
			)
		AND DI.ProductID IN (
			SELECT ProductID FROM @ProductTable
			)
		AND DI.ChargeType != 11 -- rolling commission
	ORDER BY p.PartyID
		,Di.ProductID
  
	RETURN;
END;
GO