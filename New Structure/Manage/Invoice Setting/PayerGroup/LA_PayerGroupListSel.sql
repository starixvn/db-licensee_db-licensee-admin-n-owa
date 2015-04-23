USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupListSel]
	 @PayerGroupId	INT	= 0	
AS
/*  
	 Created: 20150422@Florent
	 Task : get List Payer Group by all or by Id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all payer
		+ <> 0 specify a payer
	 Example:
		EXEC dbo.LA_PayerGroupListSel 1
*/
BEGIN	
SET NOCOUNT ON

	SELECT pg.PartyGroupId AS PayerGroupID, pg.PartyGroupName AS PayerGroupName, COUNT(pga.PartyId) AS NumberOfPayers	
		, STUFF((
				SELECT ', ' + CAST(CASE WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName ELSE p1.PartyName END AS VARCHAR)
				FROM LA_PartyGroupAssignment p
					LEFT JOIN dbo.OAS_Party p1 ON p.PartyId = p1.PartyID
					LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p1.PartyID = pd.PartyID
				WHERE pg.PartyGroupId = p.PartyGroupId					
				FOR XML PATH (''))
			  , 1, 2, '') AS PayerList				
	FROM dbo.LA_PartyGroup pg WITH (NOLOCK)		
		LEFT JOIN dbo.LA_PartyGroupAssignment pga WITH (NOLOCK) ON pg.PartyGroupId = pga.PartyGroupId		
	WHERE (@PayerGroupId = 0 OR pg.PartyGroupId = @PayerGroupId)
	GROUP BY pg.PartyGroupId, pg.PartyGroupName

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerGroupListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerGroupListSel] TO bodbAdminNet 
