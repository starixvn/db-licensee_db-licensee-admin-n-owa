ALTER PROCEDURE [dbo].[OA_FunctionsGetByFunctionID]	
	@FunctionID int
AS
/*  
 * Created: 20111125@Kos
 * Task : Get function information by function ID
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/  

SET NOCOUNT ON

SELECT	
	FunctionID
	,FunctionName
	,FunctionDesc
	,ParentID
	,ParentName
	,URL
	,CreatedDate
	,ModifiedDate
	,DisplayOrder
	,Creator
	,IsActive
	,FunctionKey	
FROM
	dbo.OA_Functions AS f WITH(NOLOCK)
WHERE f.FunctionID=@FunctionID

GO
GRANT EXECUTE ON [dbo].[OA_FunctionsGetByFunctionID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_FunctionsGetByFunctionID] TO [vnteam]  