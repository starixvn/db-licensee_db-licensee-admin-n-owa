USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_ChargeInfo] (
	@PartyIDs			VARCHAR(1000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @ProductCodes		VARCHAR(1000)
	, @System			VARCHAR(10)		= 'OA'
	, @ExcludeTest		BIT	
	)
RETURNS @tbChargeInfo TABLE (
	 ChargeID			INT
	, PartyID			INT
	, LicenseeID		INT
	, isDeposit			INT
	, AffectedDate		SMALLDATETIME
	, ProductID			INT
	, Bettype			INT				DEFAULT -1
	, DI_Rate			MONEY
	, OW_Rate			MONEY
	, PNR_Rate			MONEY
	, Fromdate			SMALLDATETIME
	, Todate			SMALLDATETIME
	)
AS
/*  Created: 20141111@Florent  
    Task : Get Charge Information
    DB: DBLIC/bodb_Licensee  
    Param's Explanation:   
		- 20150710@Florent: support product MicroGaming with multi charge rate
		- 20150825@Florent: change fiter ChargeType = 1 to ChargeType != 2 (support new ChargeType 5)
    select * FROM [LA_f_ChargeInfo_xtest]('14,15,16,17,18,25','2013-08-01','2013-08-30','NG','OA')
*/

BEGIN     
	DECLARE @SystemID INT
	SELECT @SystemID = id FROM dbo.Systems WITH (NOLOCK) WHERE SystemName = @System	
	
	DECLARE @ProductTable TABLE (ProductID smallint, ProductPrefix varchar(20))
	DECLARE @Bettype TABLE (ProductId smallint, BetTypeRef smallint, BetType smallint)
	--DECLARE @ProductCodes varchar(20) = 'MGCLC'
		
	INSERT INTO @ProductTable (ProductID, ProductPrefix)
	SELECT CASE 
			WHEN s.val = 'SB'
				THEN 0
			ELSE p3.Productid
			END
			, p3.ProductPrefix
			FROM bodb02.dbo.strSplit(@ProductCodes, ',') s
			INNER JOIN dbo.Product3rd p3 WITH (NOLOCK) ON s.val = p3.ProductPrefix
	
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

    INSERT INTO @tbChargeInfo (ChargeID , PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate)
	SELECT DI.ChargeID 
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

	INSERT INTO @tbChargeInfo (ChargeID , PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Bettype, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate)
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
	ORDER BY p.PartyID
		,Di.ProductID

    IF @ExcludeTest = 1
    DELETE @tbChargeInfo WHERE DI_Rate = 0


    --get more licensee for racing product
	IF CHARINDEX('RB', @ProductCodes) <> 0
	BEGIN
		INSERT INTO @tbChargeInfo (ChargeID, PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Bettype, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate)
		SELECT
			 0 AS ChargeID 
			, p.PartyID
			, CASE 
		 		WHEN ISNULL(pd.IsDeposit, 0) = 1
		 			THEN l.LicenseeID
		 		ELSE lb.LabelID
		 		END AS LicenseeID
			, pd.IsDeposit
			, NULL
			, pr.Productid
			, -1 AS Bettype
			, 1
			, 1
			, 1
			, @FromDate
			, @ToDate		
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.Licensees l(NOLOCK) ON p.OldRefID = l.LicenseeID AND p.PartyType = 1	
			INNER JOIN (
					SELECT CASE 
							WHEN s.val = 'SB'
								THEN 0
							ELSE p3.Productid
							END AS Productid
						 ,p3.ProductPrefix
					FROM bodb02.dbo.strSplit(@ProductCodes, ',') s
					LEFT JOIN dbo.Product3rd p3 WITH (NOLOCK) ON s.val = p3.ProductPrefix
					) pr ON pr.ProductPrefix = 'RB'
			LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
			LEFT JOIN dbo.labels lb(NOLOCK) ON l.LicenseeID = lb.LicenseeID
		WHERE p.PartyID IN (
				SELECT VAL
				FROM strSplit(@PartyIDs, ',')
				)
			AND (
				l.AffectedDate IS NOT NULL
				OR pd.IsDeposit = 0
				)
	END

    -- add more data incase trial
    IF @ExcludeTest = 0
    BEGIN
	   INSERT INTO @tbChargeInfo (ChargeID, PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Bettype, DI_Rate, OW_Rate, PNR_Rate, Fromdate, Todate)
	   (
			SELECT DISTINCT 0 AS ChargeID
				, f1.Val PartyId
				, CASE 
					WHEN ISNULL(pd.IsDeposit, 0) = 1
						THEN p.OldRefID
					ELSE lb.LabelID
					END AS LicenseeID
				, pd.IsDeposit
				, cte.AffectedDate
				, f2.Productid
				, - 1 AS Bettype
				, 0 DI_Rate
				, 0 OW_Rate
				, 0 PNR_Rate
				, @FromDate
				--, DATEADD(D, -1, cte.AffectedDate) 
				, CASE 
					WHEN @ToDate >= DATEADD(D, - 1, cte.AffectedDate)
						THEN DATEADD(D, - 1, cte.AffectedDate)
					ELSE @ToDate
					END
			FROM strSplit(@PartyIDs, ',') f1
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON f1.Val = p.PartyID
				LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
				LEFT JOIN @Cte_AffectDate cte ON p.PartyID = cte.PartyID
				INNER JOIN @ProductTable f2 ON cte.ProductID = f2.Productid
			WHERE @FromDate <= cte.AffectedDate
				AND NOT EXISTS (
					SELECT Productid
					FROM dbo.LA_Product3rdSub WITH (NOLOCK)
					WHERE cte.ProductID = Productid
					)

			UNION ALL

			SELECT DISTINCT 0 AS ChargeID
				, f1.Val PartyId
				, CASE 
					WHEN ISNULL(pd.IsDeposit, 0) = 1
						THEN p.OldRefID
					ELSE lb.LabelID
					END AS LicenseeID
				, pd.IsDeposit
				, cte.AffectedDate
				, f2.Productid
				, sbr.BetTypeRef AS Bettype
				, 0 DI_Rate
				, 0 OW_Rate
				, 0 PNR_Rate
				, @FromDate
				--, DATEADD(D, -1, cte.AffectedDate) 
				, CASE 
					WHEN @ToDate >= DATEADD(D, - 1, cte.AffectedDate)
						THEN DATEADD(D, - 1, cte.AffectedDate)
					ELSE @ToDate
					END
			FROM strSplit(@PartyIDs, ',') f1
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON f1.Val = p.PartyID
				LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
				LEFT JOIN @Cte_AffectDate cte ON p.PartyID = cte.PartyID
				INNER JOIN @ProductTable f2 ON cte.ProductID = f2.Productid
				INNER JOIN dbo.OAS_ChargeInfoSub sub WITH (NOLOCK) ON sub.ProductID = cte.ProductID
				INNER JOIN @Bettype sbr ON sbr.BetTypeRef = sub.BettypeRef
			WHERE @FromDate <= cte.AffectedDate
				AND EXISTS (SELECT Productid FROM dbo.LA_Product3rdSub WITH (NOLOCK)WHERE cte.ProductID = Productid)
	   )
	END

	RETURN
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_f_ChargeInfo] TO [vnteam] 
GO
GRANT SELECT ON [dbo].[LA_f_ChargeInfo] TO bodbAdminNet 