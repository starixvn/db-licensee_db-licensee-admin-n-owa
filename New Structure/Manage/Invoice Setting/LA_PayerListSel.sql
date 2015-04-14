USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerListSel]
	 @PayerId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get List payer by all or biller id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all payer
		+ <> 0 specify a payer 
	 Example:
		EXEC dbo.LA_PayerListSel 0
*/
SET NOCOUNT ON
BEGIN
	SELECT PartyID, PartyName
	FROM dbo.OAS_Party WITH (NOLOCK)
	WHERE (@PayerId = 0 OR PartyID = @PayerId)
		AND PartyType = 1
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerListSel] TO bodbAdminNet 