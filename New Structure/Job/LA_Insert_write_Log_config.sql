/*
    Author: Florent.Nguyen
    Date : 2014-10-15
*/
USE bodb_licensee
GO
UPDATE dbo.OAS_Party WITH (ROWLOCK) SET PartyName ='ONEWorks' WHERE PartyName = 'Oneworks'
GO 
IF EXISTS (SELECT TOP 1 1 FROM dbo.OA_LogAction WITH (NOLOCK) WHERE ActionID >= 600)
BEGIN
    DELETE dbo.OA_LogAction WHERE ActionID >= 600
END

BEGIN
    INSERT INTO dbo.OA_LogAction(ActionID,ActionTypeID,SPName,
    ActionNameEN,ActionNameCH,ActionNameCS,ActionNameJP,ActionNameIT,ActionNameTH,ActionNameKO,
    XsltContent,IsInternal)
    SELECT 600,6,'LA_FunctionIns',
    'Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function'
    ,'',0
    UNION
    SELECT 601,6,'LA_FunctionUpd',
    'Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function','Create/Update Function'
    ,'',0
    UNION
    SELECT 602,6,'LA_FunctionPartysModify',
    'Create/Update Function Party','Create/Update Function Party','Create/Update Function Party','Create/Update Function Party','Create/Update Function Party','Create/Update Function Party','Create/Update Function Party'
    ,'',0
    UNION
    SELECT 603,6,'LA_UserFunctionModify',
    'Create/Update User Function','Create/Update User Function','Create/Update User Function','Create/Update User Function','Create/Update User Function','Create/Update User Function','Create/Update User Function'
    ,'',0
    UNION
    SELECT 604,6,'LA_UsersModify_Create',
    'Create User','Create User','Create User','Create User','Create User','Create User','Create User'
    ,'',0
    UNION
    SELECT 605,6,'LA_UsersModify',
    'Update User','Update User','Update User','Update User','Update User','Update User','Update User'
    ,'',0
    UNION
    SELECT 606,6,'LA_UserPartysModify',
    'Create/Update User Party','Create/Update User Party','Create/Update User Party','Create/Update User Party','Create/Update User Party','Create/Update User Party','Create/Update User Party'
    ,'',0
    UNION
    SELECT 607,6,'LA_UserPasswordUpd',
    'Update User Password','Update User Password','Update User Password','Update User Password','Update User Password','Update User Password','Update User Password'
    ,'',0
    UNION
    SELECT 608,6,'LA_UserPwdReset',
    'Reset User Password','Reset User Password','Reset User Password','Reset User Password','Reset User Password','Reset User Password','Reset User Password'
    ,'',0
    UNION
    SELECT 609,6,'LA_UserUpdIsActive',
    'Update User Status is Active/No-Active','Update User Status is Active/No-Active','Update User Status is Active/No-Active','Update User Status is Active/No-Active','Update User Status is Active/No-Active','Update User Status is Active/No-Active','Update User Status is Active/No-Active'
    ,'',0
END