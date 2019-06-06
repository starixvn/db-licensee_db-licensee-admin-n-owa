/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_Products3rd] (@Products VARCHAR(1000))
RETURNS @tbProducts TABLE (ProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(100))
AS

/*  Created: 20150413@Florent
    Task: Get Products Information
    DB: DBCUST.bodb_Licensee, DBLIC.bodb_licensee
    
	Revisions:
		- 20150413@Florent: Initialize function
*/

BEGIN   
	IF ISNULL(@Products,'') = ''
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
		
		UNION
		
		SELECT 0, 'SB', 'Sportsbook'

	END
	ELSE
	BEGIN
		IF CHARINDEX( 'SB', @Products) <> 0
		BEGIN
			INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
			SELECT 0, 'SB', 'Sportsbook'				
		END

		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
		WHERE ProductPrefix IN (SELECT val FROM dbo.strSplit(@Products,','))
			AND ProductId <> 0
			
	END
	
	DELETE @tbProducts WHERE ProductID IS NULL

	RETURN
END
GO