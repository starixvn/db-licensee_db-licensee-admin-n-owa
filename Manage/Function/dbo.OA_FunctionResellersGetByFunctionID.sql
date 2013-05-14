ALTER PROCEDURE [dbo].[OA_FunctionResellersGetByFunctionID]
	@FunctionID int
AS
/*  
 * Created: 20111124@Kos
 * Task : Get reseller(s) of a function
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/
SET NOCOUNT ON


SELECT	
	r.ResellerID
	,r.ResellerName		
FROM
	dbo.OA_FunctionResellers AS fr WITH(NOLOCK)
	INNER JOIN dbo.Resellers AS r WITH(NOLOCK) ON fr.ResellerID=r.ResellerID	
WHERE
	fr.FunctionID = FunctionID
	
GO
GRANT EXECUTE ON [dbo].[OA_FunctionResellersGetByFunctionID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionResellersGetByFunctionID] TO [vnteam] 	