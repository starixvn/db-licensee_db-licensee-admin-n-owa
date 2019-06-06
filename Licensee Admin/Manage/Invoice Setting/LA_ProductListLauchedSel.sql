/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ProductListLauchedSel]
	@PayerId	INT	= 0	
AS
/*  
	 Created: 20170224@scofield.huynh
	 Task : get All Launched Products
	 DB: DBLIC.bodb_Licensee  
   
	 Revisions:     	
		- 20170301@Scofield: Update to exclude 'RB', 'BG', 'PTCS', 'HF' and inclucde 'SB' [#70050]
	 Example:
		EXEC dbo.LA_ProductListLauchedSel
*/
BEGIN
	SET NOCOUNT ON	
	
	SELECT DISTINCT p.ProductID, p.ProductPrefix, p.ProductName
	FROM dbo.LA_f_Products3rd('') p
	INNER JOIN LicenseeProduct3rd lp ON p.ProductID = lp.ProductID
	WHERE lp.LicenseeID IN (
		SELECT
			CASE 
			WHEN ISNULL(pd.IsDeposit, 0) = 1
				THEN p.OldRefID
			ELSE lb.LabelID
			END AS LicenseeID
		FROM OAS_Party p
		LEFT JOIN OAS_PartyDetail pd ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
		WHERE p.PartyID = @PayerId
	) AND p.ProductPrefix NOT IN ('RB', 'BG', 'PTCS', 'HF')
	
	UNION
	
	SELECT p.ProductID, p.ProductPrefix, p.ProductName
	FROM dbo.LA_f_Products3rd('') p
	WHERE p.ProductPrefix = 'SB'
	
END
GO