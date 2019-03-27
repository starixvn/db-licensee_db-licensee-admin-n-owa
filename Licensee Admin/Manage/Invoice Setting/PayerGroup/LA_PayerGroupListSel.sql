/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupListSel]
	 @PayerGroupId	INT	= 0	
	 , @PayerID		INT = 0
AS
/*  
	 Created: 20150422@Florent
	 Task : get List Payer Group by all or by Id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:
		  - 20180327@Parsons: Apply min fee rule for discount calculation [#109997]     		  
	 Params:
		+ 0 get all payer
		+ <> 0 specify a payer
	 Example:
		EXEC dbo.LA_PayerGroupListSel @PayerGroupId = 0 ,@PayerID = 14
*/
BEGIN	
SET NOCOUNT ON 

	DECLARE @Result AS TABLE (PartyGroupId INT, PartyGroupName VARCHAR(50), NumberOfPayers INT, PayerList VARCHAR(1000), TotalMinFee MONEY)

	INSERT INTO @Result(PartyGroupId , PartyGroupName, NumberOfPayers)
	SELECT pg.PartyGroupId AS PayerGroupID, pg.PartyGroupName AS PayerGroupName, COUNT(pga.PartyId) AS NumberOfPayers
	FROM dbo.LA_PartyGroup pg WITH (NOLOCK)		
		LEFT JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK) ON pg.PartyGroupId = pga.PartyGroupId		
	WHERE (@PayerGroupId = 0 OR pg.PartyGroupId = @PayerGroupId)
		AND (@PayerID = 0 OR pga.PartyId = @PayerID)
	GROUP BY pg.PartyGroupId, pg.PartyGroupName

	-- Update PayerList
	UPDATE r
	SET r.PayerList = STUFF((
				SELECT ', ' + CAST(CASE WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName ELSE p1.PartyName END AS VARCHAR)
				FROM dbo.LA_PartyGroupAssignment p WITH (NOLOCK)
					LEFT JOIN dbo.OAS_Party p1 WITH (NOLOCK) ON p.PartyId = p1.PartyID
					LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p1.PartyID = pd.PartyID
				WHERE r.PartyGroupId = p.PartyGroupId					
				FOR XML PATH ('')), 1, 2, '') 			
	FROM @Result r

	-- Update TotalMinFee
	;WITH cte_Data AS(
		SELECT pa.PartyGroupId, pa.PartyId, MAX(MinFeeId) AS MinFeeId 
		FROM LA_PartyGroupAssignment pa WITH(NOLOCK)
		INNER JOIN LA_MinFee mf WITH(NOLOCK) ON pa.PartyId = mf.PartyId
		GROUP BY pa.PartyGroupId, pa.PartyId),
	cte_Data2 AS(
		SELECT PartyGroupId, SUM(ISNULL(mf.FeeAmount, 0)) AS TotalMinFee
		FROM cte_Data d
		INNER JOIN LA_MinFee mf WITH(NOLOCK) ON d.MinFeeId = mf.MinFeeId
		GROUP BY PartyGroupId)
	
	UPDATE r
	SET r.TotalMinFee = ISNULL(d.TotalMinFee, 0)			
	FROM @Result r
	LEFT JOIN cte_Data2 d ON r.PartyGroupId = d.PartyGroupId
	
	SELECT * FROM @Result
END
GO