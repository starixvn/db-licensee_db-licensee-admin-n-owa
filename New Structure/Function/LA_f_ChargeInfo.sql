USE [bodb_licensee]
GO
/****** Object:  UserDefinedFunction [dbo].[LA_f_ChargeInfo]    Script Date: 18/11/2014 13:38:46 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_ChargeInfo] (
	 @PartyIDs	VARCHAR(1000)
	,@FromDate	DATETIME
	,@ToDate		DATETIME
	,@ProductCodes VARCHAR(1000)
	,@System		VARCHAR(10)
	)
RETURNS @tbChargeInfo TABLE (
	PartyID		INT
	,LicenseeID	INT
	,isDeposit	INT
	,AffectedDate	SMALLDATETIME
	,ProductID	INT
	,Rate		MONEY
	,Fromdate		SMALLDATETIME
	,Todate		SMALLDATETIME
	)
AS
/*  Created: 20141111@Florent  
    Task : Get Charge Information
    DB: DB052/bodb_Licensee  
    Param's Explanation:   
    select * FROM [LA_f_ChargeInfo]('14,15,16,17,18,25','2013-08-01','2013-08-30','NG','OA')
*/

BEGIN     
     DECLARE @SystemID INT
	SELECT @SystemID = id FROM dbo.Systems WITH (NOLOCK) WHERE SystemName = @System	
	
	;WITH Cte_AffectDate
	AS (
		SELECT MIN(FromDate) AS AffectedDate
			,FromParty AS PartyID
			,ci.ProductID
		FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
		WHERE ChargeType = 1
			AND p.PartyID IN (
				SELECT VAL
				FROM strSplit(@PartyIDs, ',')
				)
		GROUP BY FromParty
			,ci.ProductID
		)
     INSERT INTO @tbChargeInfo (PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,Rate,Fromdate,Todate)
	SELECT p.PartyID
		,CASE 
			WHEN ISNULL(pd.IsDeposit, 0) = 1
				THEN l.LicenseeID
			ELSE lb.LabelID
			END AS LicenseeID
		,pd.IsDeposit
		,cte.AffectedDate
		,DI.ProductID
		,CASE 
			WHEN DI.ProductID IN (0,3) --SB and BA				
				THEN DI.Rate
			WHEN DI.ProductID IN (5,4,2,6) -- VS NG,LC,CS
				THEN
				    CASE WHEN (PNR.rate IS NOT NULL AND PNR.ChargeType = 1)
						  THEN (ISNULL(OW.Rate,0) - ISNULL(PNR.rate,0))
					    WHEN (PNR.Rate IS NOT NULL AND PNR.ChargeType = 3 )
						  THEN (CASE WHEN ISNULL(DI.Rate,0) = 0 THEN 1 ELSE ISNULL(DI.Rate,0) END * ISNULL(OW.Rate,0) * ISNULL(PNR.rate,0))					   
					   ELSE CASE WHEN DI.Rate  = 0 THEN OW.Rate ELSE DI.Rate END
				    END			
			END OW_Rate
		,CASE 
			WHEN @FromDate <= DI.FromDate
				THEN DI.FromDate
			ELSE @FromDate
			END
		,CASE 
			WHEN @ToDate >= DI.ToDate
				THEN DI.ToDate
			ELSE @ToDate
			END
	FROM dbo.OAS_Party p WITH (NOLOCK)
	INNER JOIN dbo.Licensees l WITH (NOLOCK) ON p.OldRefID = l.LicenseeID AND p.PartyType = 1
	INNER JOIN dbo.OAS_ChargeInfo DI WITH (NOLOCK) ON DI.FromParty = p.PartyID	AND DI.ChargeType = 1
	INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON DI.ChargeID = cs.ChargeID AND cs.SystemID = @SystemID
	LEFT JOIN dbo.OAS_ChargeInfo OW WITH (NOLOCK) ON DI.ParentChargeID = OW.ChargeID
	LEFT JOIN dbo.OAS_ChargeInfo PNR WITH (NOLOCK) ON OW.ParentChargeID = PNR.ChargeID
	LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
	LEFT JOIN dbo.labels lb(NOLOCK) ON l.LicenseeID = lb.LicenseeID
	LEFT JOIN Cte_AffectDate cte ON cte.PartyID = p.PartyID
		AND DI.ProductID = cte.ProductID
	WHERE p.PartyID IN (
			SELECT VAL
			FROM strSplit(@PartyIDs, ',')
			)
		AND (
			l.AffectedDate IS NOT NULL
			OR pd.IsDeposit = 0
			)
		AND (
			@FromDate BETWEEN DI.FromDate AND DI.ToDate
			OR @ToDate BETWEEN DI.FromDate AND DI.ToDate
			)
		AND DI.ProductID IN (
			SELECT CASE 
					WHEN s.val = 'SB'
						THEN 0
					ELSE p3.Productid
					END
			FROM bodb02.dbo.strSplit(@ProductCodes, ',') s
			LEFT JOIN dbo.Product3rd p3 WITH (NOLOCK) ON s.val = p3.ProductPrefix
			)
	ORDER BY p.PartyID
		,Di.ProductID


    --get more licensee for racing product
	IF CHARINDEX('RB', @ProductCodes) <> 0
     INSERT INTO @tbChargeInfo (PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,Rate,Fromdate,Todate)
	SELECT p.PartyID
		,CASE 
			WHEN ISNULL(pd.IsDeposit, 0) = 1
				THEN l.LicenseeID
			ELSE lb.LabelID
			END AS LicenseeID
		,pd.IsDeposit
		,NULL
		,pr.Productid
		,1
		,@FromDate
		,@ToDate		
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
	RETURN
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_f_ChargeInfo] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_f_ChargeInfo] TO bodbAdminNet 