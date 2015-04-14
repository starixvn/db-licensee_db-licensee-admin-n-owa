USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerListSel]
	 @BillerId	INT	= 0	
AS
/*  
	 Created: 20150408@Florent
	 Task : get List Biller by all or biller name
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all biller
		+ <> 0 specify a biller 
	 Example:
		EXEC dbo.LA_BillerListSel 0
*/
SET NOCOUNT ON
BEGIN	

	WITH cte_BillerPayer(FromPartyId, ToPartyID)
	AS 
	(
		SELECT FromPartyId, ToPartyID 
		FROM dbo.LA_InvoiceSetting WITH (NOLOCK)
		GROUP BY FromPartyId, ToPartyID 	
	)
	SELECT b.PartyID AS BillerID, b.BillerName, b.BillerFullName, b.CompanyName, COUNT(i.FromPartyId) AS NumberOfPayers	
		,STUFF((
				SELECT ', ' + CAST(pp.PartyName AS VARCHAR)
				FROM cte_BillerPayer ii
					LEFT JOIN dbo.OAS_Party pp ON ii.FromPartyId = pp.PartyID
				WHERE i.ToPartyID = ii.ToPartyID
				FOR XML PATH (''))
			  , 1, 2, '') AS PayerList
		, b.StatusId
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID		
		LEFT JOIN cte_BillerPayer i ON i.ToPartyId = p.PartyID
	WHERE p.PartyType = 4
		AND (@BillerId = 0 OR p.PartyID = @BillerId)
	GROUP BY b.PartyID, b.BillerName, b.CompanyName, ToPartyID, b.BillerFullName, b.StatusId

END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerListSel] TO bodbAdminNet 