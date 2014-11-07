USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Party_TotalTrans]    Script Date: 07/11/2014 10:27:31 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OAS_Party_TotalTrans    Script Date: 12/31/2013 10:38:18  ******/
ALTER PROCEDURE [dbo].[OAS_Party_TotalTrans] 
	 @FromDate SMALLDATETIME
	,@ToDate SMALLDATETIME
	,@ExcludeTest BIT = 1
AS
/*  
 * Created by : 20131126@Francis 
 * Task  : Get all licensees (compatible with the new structure) for Total Trans report 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	- 20141031@Florent: Apply new Structure Using SystemMapping
 * Param's Explanation:    
 *  - @ExcludeTest: to exclude Spondemo (a test licensee)
 */
BEGIN
	SET NOCOUNT ON

	SELECT @Fromdate = ltrim(rtrim(@Fromdate))
		,@Todate = ltrim(rtrim(@Todate))

	SELECT DISTINCT ci.ChargeID
		,ci.FromParty AS PartyID
		,p.PartyName AS PartyName
		,ci.ParentChargeID
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	     INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
		LEFT JOIN dbo.LA_ChargeInfo_MinFee cm WITH (NOLOCK) ON ci.ChargeID = cm.ChargeID
	WHERE (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate
			OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
			)
		AND ci.ChargeType = 2
		AND ci.ProductID = 0
		AND ci.ToParty IN (
			SELECT p1.PartyID
			FROM OAS_Party p1(NOLOCK)
			WHERE p1.PartyName IN ('Oneworks', 'BCH', 'LDL')
			)
		AND (
			(@ExcludeTest = 0)
			OR (
				@ExcludeTest = 1
				AND ci.FromParty NOT IN (
					SELECT p2.PartyID
					FROM OAS_Party p2(NOLOCK)
					WHERE p2.PartyName IN ('spondemo', 'Demo')
					)
				)
			)
		AND ci.MinAmount = 0
	ORDER BY ci.ParentChargeID ASC
END
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Party_TotalTrans] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Party_TotalTrans] TO bodbAdminNet 