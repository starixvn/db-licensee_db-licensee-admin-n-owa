 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go


ALTER  PROCEDURE [dbo].[OA_ProductGetAll]
AS
/*  
 * Created  : 20130108@Jim
 * Task  : Licensee Product & feature management
 * DB   : DB052.bodb02  
 * Revisions :  
	
 * Param's Explanation:    
 *  
 *  
 *
*/
BEGIN
	SELECT DISTINCT Productid,ProductName
	FROM bodb_licensee.dbo.Product3rd WITH (NOLOCK)
	ORDER BY Productid
END 

GO
GRANT EXECUTE ON [dbo].[OA_ProductGetAll] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_ProductGetAll] TO [vnteam]
